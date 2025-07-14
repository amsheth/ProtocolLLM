/**
 * @brief Full-duplex UART Controller Module
 * @details Implements a UART transmitter and receiver with configurable baud rate,
 *          optional parity, and 2 stop bits.
 *
 * @param SYS_CLK_FREQ System clock frequency in Hz (e.g., 50_000_000 for 50MHz)
 * @param BAUD_RATE Desired baud rate in bits per second (e.g., 9600)
 * @param PARITY_EN Enable parity bit. 1 = Enabled, 0 = Disabled.
 *                  If enabled, data_in[8] is the parity bit to be sent, and
 *                  the receiver checks the incoming parity bit.
 */
module UART_driver #(
    parameter SYS_CLK_FREQ = 50_000_000,
    parameter BAUD_RATE    = 9600,
    parameter PARITY_EN    = 1
) (
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous active-high reset
    
    // Transmitter Interface
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [8:0] data_in,    // Data to be transmitted (data_in[7:0] is data, data_in[8] is parity if PARITY_EN=1)
    output logic       TX,         // UART transmit line
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    
    // Receiver Interface
    input  logic       RX,         // UART receive line
    output logic [8:0] data_out,   // Received data (data_out[7:0] is data, data_out[8] is received parity bit)
    output logic       UART_Error  // High if framing or parity error detected
);

    //--------------------------------------------------------------------------
    // Local Parameters and Constants
    //--------------------------------------------------------------------------
    localparam CLKS_PER_BAUD = SYS_CLK_FREQ / BAUD_RATE;

    //--------------------------------------------------------------------------
    // Baud Rate Generator
    //--------------------------------------------------------------------------
    logic baud_tick;
    int   clk_counter = 0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 0;
            baud_tick   <= 1'b0;
        end else begin
            baud_tick <= 1'b0;
            if (clk_counter == CLKS_PER_BAUD - 1) begin
                clk_counter <= 0;
                baud_tick   <= 1'b1;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end
    end

    //==========================================================================
    // TRANSMITTER LOGIC
    //==========================================================================
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START_BIT,
        TX_DATA_BITS,
        TX_PARITY_BIT,
        TX_STOP_BITS
    } tx_state_t;

    tx_state_t tx_state;
    logic [3:0] tx_bit_count;
    logic [11:0] tx_shift_reg; // 1 start + 8 data + 1 parity + 2 stop

    // Combinational logic for TX outputs
    assign TX         = (tx_state == TX_IDLE) ? 1'b1 : tx_shift_reg[0];
    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy  = ~UART_Ready;

    // TX State Machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state     <= TX_IDLE;
            tx_bit_count <= 0;
            tx_shift_reg <= 0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    if (UART_Start) begin
                        tx_state     <= TX_START_BIT;
                        // Frame format: {2'b11, parity_bit, data_bits, 1'b0}
                        // LSB is start bit (0), MSBs are stop bits (1,1)
                        tx_shift_reg <= {2'b11, (PARITY_EN ? data_in[8] : 1'b1), data_in[7:0], 1'b0};
                    end
                end

                TX_START_BIT: begin
                    if (baud_tick) begin
                        tx_state     <= TX_DATA_BITS;
                        tx_bit_count <= 0;
                        tx_shift_reg <= tx_shift_reg >> 1;
                    end
                end

                TX_DATA_BITS: begin
                    if (baud_tick) begin
                        tx_shift_reg <= tx_shift_reg >> 1;
                        if (tx_bit_count == 7) begin
                            tx_bit_count <= 0;
                            tx_state     <= PARITY_EN ? TX_PARITY_BIT : TX_STOP_BITS;
                        end else begin
                            tx_bit_count <= tx_bit_count + 1;
                        end
                    end
                end

                TX_PARITY_BIT: begin
                    if (baud_tick) begin
                        tx_state     <= TX_STOP_BITS;
                        tx_shift_reg <= tx_shift_reg >> 1;
                    end
                end

                TX_STOP_BITS: begin
                    if (baud_tick) begin
                        tx_shift_reg <= tx_shift_reg >> 1;
                        // After first stop bit, count is 0. After second, it's 1.
                        if (tx_bit_count == 1) begin
                            tx_state     <= TX_IDLE;
                            tx_bit_count <= 0;
                        end else begin
                            tx_bit_count <= tx_bit_count + 1;
                        end
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    //==========================================================================
    // RECEIVER LOGIC
    //==========================================================================
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START_BIT,
        RX_DATA_BITS,
        RX_PARITY_BIT,
        RX_STOP_BITS,
        RX_CLEANUP
    } rx_state_t;

    rx_state_t rx_state;
    logic [3:0]  rx_bit_count;
    logic [8:0]  rx_shift_reg;
    logic        rx_framing_error;
    logic        rx_parity_error;
    logic        rx_sync_1, rx_sync_2;
    int          rx_sample_count;

    // Synchronize asynchronous RX input to prevent metastability
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync_1 <= 1'b1;
            rx_sync_2 <= 1'b1;
        end else begin
            rx_sync_1 <= RX;
            rx_sync_2 <= rx_sync_1;
        end
    end

    // RX State Machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state          <= RX_IDLE;
            rx_bit_count      <= 0;
            rx_shift_reg      <= 0;
            rx_sample_count   <= 0;
            rx_framing_error  <= 1'b0;
            rx_parity_error   <= 1'b0;
            data_out          <= 0;
            UART_Error        <= 1'b0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    rx_framing_error <= 1'b0;
                    rx_parity_error  <= 1'b0;
                    UART_Error       <= 1'b0;
                    // Detect start bit (falling edge)
                    if (rx_sync_2 == 1'b0 && rx_sync_1 == 1'b1) begin
                        rx_state        <= RX_START_BIT;
                        rx_sample_count <= 0;
                    end
                end

                RX_START_BIT: begin
                    // Wait for the middle of the start bit to sample
                    if (rx_sample_count == (CLKS_PER_BAUD / 2) - 1) begin
                        rx_sample_count <= 0;
                        // If line is still low, it's a valid start bit
                        if (rx_sync_2 == 1'b0) begin
                            rx_state <= RX_DATA_BITS;
                        end else begin
                            // Glitch, not a real start bit
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_sample_count <= rx_sample_count + 1;
                    end
                end

                RX_DATA_BITS: begin
                    if (baud_tick) begin
                        rx_shift_reg <= {rx_sync_2, rx_shift_reg[8:1]};
                        if (rx_bit_count == 7) begin
                            rx_bit_count <= 0;
                            rx_state     <= PARITY_EN ? RX_PARITY_BIT : RX_STOP_BITS;
                        end else begin
                            rx_bit_count <= rx_bit_count + 1;
                        end
                    end
                end

                RX_PARITY_BIT: begin
                    if (baud_tick) begin
                        rx_shift_reg <= {rx_sync_2, rx_shift_reg[8:1]};
                        rx_state     <= RX_STOP_BITS;
                    end
                end

                RX_STOP_BITS: begin
                    if (baud_tick) begin
                        // Check first stop bit. Must be high.
                        if (rx_sync_2 == 1'b0) begin
                            rx_framing_error <= 1'b1;
                        end
                        
                        // After sampling the first stop bit, we wait one more baud tick
                        // for the second stop bit period to end before cleaning up.
                        if (rx_bit_count == 0) begin
                            rx_bit_count <= 1;
                        end else begin
                            rx_state <= RX_CLEANUP;
                        end
                    end
                end

                RX_CLEANUP: begin
                    // Check parity if enabled
                    if (PARITY_EN) begin
                        // Received data is now in rx_shift_reg[7:0], parity bit in rx_shift_reg[8]
                        // Note: XOR reduction (^ operator) checks for ODD parity.
                        // We check for EVEN parity, so we expect the result to be 0.
                        if ((^rx_shift_reg[7:0]) != rx_shift_reg[8]) begin
                            rx_parity_error <= 1'b1;
                        end
                    end
                    
                    data_out   <= rx_shift_reg;
                    UART_Error <= rx_framing_error | rx_parity_error;
                    rx_state   <= RX_IDLE;
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule