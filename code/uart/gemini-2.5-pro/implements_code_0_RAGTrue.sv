/**
 * @brief UART (Universal Asynchronous Receiver-Transmitter) Controller
 *
 * This module implements a full-duplex UART controller with configurable baud rates.
 * It handles transmission and reception of 8-bit data frames with one start bit
 * and one stop bit.
 *
 * @param p_SYS_CLK_FREQ System Clock Frequency in Hz (e.g., 50MHz)
 * @param p_BAUD_RATE    Desired Baud Rate (e.g., 9600, 115200)
 */
module UART_driver #(
    parameter p_SYS_CLK_FREQ = 50_000_000, // Default to 50 MHz
    parameter p_BAUD_RATE    = 115200      // Default to 115200 baud
) (
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset (active high)
    // Transmitter Interface
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    output logic       TX,         // UART transmit line
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    // Receiver Interface
    input  logic       RX,         // UART receive line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Error  // High if framing or parity error detected
);

    //--------------------------------------------------------------------------
    // Internal Parameters and Types
    //--------------------------------------------------------------------------
    // Use 16x oversampling for robust bit sampling
    localparam c_OVERSAMPLE_RATE = 16;
    localparam c_CLKS_PER_TICK   = p_SYS_CLK_FREQ / (p_BAUD_RATE * c_OVERSAMPLE_RATE);
    localparam c_SAMPLE_POINT    = c_OVERSAMPLE_RATE / 2;

    // Transmitter State Machine
    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START_BIT,
        TX_DATA_BITS,
        TX_STOP_BIT
    } tx_state_e;

    // Receiver State Machine
    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START_BIT,
        RX_DATA_BITS,
        RX_STOP_BIT
    } rx_state_e;

    //--------------------------------------------------------------------------
    // Baud Rate Tick Generator
    //--------------------------------------------------------------------------
    logic       baud_tick;
    int unsigned tick_counter = 0;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_counter <= 0;
            baud_tick    <= 1'b0;
        end else begin
            baud_tick <= 1'b0;
            if (tick_counter == c_CLKS_PER_TICK - 1) begin
                tick_counter <= 0;
                baud_tick    <= 1'b1;
            end else begin
                tick_counter <= tick_counter + 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Transmitter Logic
    //--------------------------------------------------------------------------
    tx_state_e   tx_state_reg, tx_state_next;
    logic [3:0]  tx_tick_count; // Counts 0-15 for oversampling
    logic [2:0]  tx_bit_count;  // Counts 0-7 for data bits
    logic [7:0]  tx_data_reg;   // Latched data for transmission

    // Transmitter sequential logic (registers)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state_reg <= TX_IDLE;
            tx_tick_count <= '0;
            tx_bit_count  <= '0;
            tx_data_reg   <= '0;
            TX            <= 1'b1; // UART line is high when idle
            UART_Busy     <= 1'b0;
        end else begin
            tx_state_reg <= tx_state_next;
            TX           <= TX; // Keep previous value unless changed
            UART_Busy    <= UART_Busy;

            if (tx_state_next != tx_state_reg) begin // Reset counters on state change
                tx_tick_count <= '0;
                tx_bit_count  <= '0;
            end

            case (tx_state_reg)
                TX_IDLE: begin
                    if (UART_Start) begin
                        tx_data_reg <= data_in;
                        UART_Busy   <= 1'b1;
                        TX          <= 1'b0; // Start bit
                    end
                end
                TX_START_BIT: begin
                    if (baud_tick) begin
                        if (tx_tick_count == c_OVERSAMPLE_RATE - 1) begin
                            tx_tick_count <= '0;
                            TX            <= tx_data_reg[0]; // First data bit
                        end else begin
                            tx_tick_count <= tx_tick_count + 1;
                        end
                    end
                end
                TX_DATA_BITS: begin
                    if (baud_tick) begin
                        if (tx_tick_count == c_OVERSAMPLE_RATE - 1) begin
                            tx_tick_count <= '0;
                            tx_bit_count  <= tx_bit_count + 1;
                            if (tx_bit_count == 7) begin
                                TX <= 1'b1; // Stop bit
                            end else begin
                                TX <= tx_data_reg[tx_bit_count + 1];
                            end
                        end else begin
                            tx_tick_count <= tx_tick_count + 1;
                        end
                    end
                end
                TX_STOP_BIT: begin
                    if (baud_tick) begin
                        if (tx_tick_count == c_OVERSAMPLE_RATE - 1) begin
                            tx_tick_count <= '0;
                            UART_Busy     <= 1'b0;
                        end else begin
                            tx_tick_count <= tx_tick_count + 1;
                        end
                    end
                end
            endcase
        end
    end

    // Transmitter combinational logic (state transitions)
    always_comb begin
        tx_state_next = tx_state_reg;
        case (tx_state_reg)
            TX_IDLE:      if (UART_Start) tx_state_next = TX_START_BIT;
            TX_START_BIT: if (baud_tick && tx_tick_count == c_OVERSAMPLE_RATE - 1) tx_state_next = TX_DATA_BITS;
            TX_DATA_BITS: if (baud_tick && tx_tick_count == c_OVERSAMPLE_RATE - 1 && tx_bit_count == 7) tx_state_next = TX_STOP_BIT;
            TX_STOP_BIT:  if (baud_tick && tx_tick_count == c_OVERSAMPLE_RATE - 1) tx_state_next = TX_IDLE;
        endcase
    end

    // Transmitter status outputs
    assign UART_Ready = (tx_state_reg == TX_IDLE);

    //--------------------------------------------------------------------------
    // Receiver Logic
    //--------------------------------------------------------------------------
    rx_state_e   rx_state_reg, rx_state_next;
    logic [3:0]  rx_tick_count; // Counts 0-15 for oversampling
    logic [2:0]  rx_bit_count;  // Counts 0-7 for data bits
    logic [7:0]  rx_data_reg;   // Shift register for incoming data
    logic        rx_sync1, rx_sync2, rx_sync3; // RX line synchronizer

    // Synchronize asynchronous RX input to system clock to prevent metastability
    always_ff @(posedge clk) begin
        rx_sync1 <= RX;
        rx_sync2 <= rx_sync1;
        rx_sync3 <= rx_sync2;
    end

    // Receiver sequential logic (registers)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state_reg <= RX_IDLE;
            rx_tick_count <= '0;
            rx_bit_count  <= '0;
            rx_data_reg   <= '0;
            data_out      <= '0;
            UART_Error    <= 1'b0;
        end else begin
            rx_state_reg <= rx_state_next;
            data_out     <= data_out; // Latch previous value
            UART_Error   <= UART_Error; // Latch previous value

            if (rx_state_next != rx_state_reg) begin // Reset counters on state change
                rx_tick_count <= '0;
                rx_bit_count  <= '0;
            end

            case (rx_state_reg)
                RX_IDLE: begin
                    UART_Error <= 1'b0; // Clear error on new reception attempt
                    if (rx_sync2 == 1'b1 && rx_sync3 == 1'b0) begin // Detect falling edge (start)
                        rx_tick_count <= '0;
                    end
                end
                RX_START_BIT: begin
                    if (baud_tick) begin
                        if (rx_tick_count == c_SAMPLE_POINT - 1) begin
                            if (rx_sync3 == 1'b0) begin // Confirm it's a valid start bit
                                // Valid start bit, do nothing, wait for next state
                            end else begin
                                // Glitch, go back to idle
                            end
                        end
                        rx_tick_count <= rx_tick_count + 1;
                    end
                end
                RX_DATA_BITS: begin
                    if (baud_tick) begin
                        if (rx_tick_count == c_SAMPLE_POINT - 1) begin
                            rx_data_reg[rx_bit_count] <= rx_sync3; // Sample bit
                        end
                        if (rx_tick_count == c_OVERSAMPLE_RATE - 1) begin
                            rx_tick_count <= '0;
                            rx_bit_count  <= rx_bit_count + 1;
                        end else begin
                            rx_tick_count <= rx_tick_count + 1;
                        end
                    end
                end
                RX_STOP_BIT: begin
                    if (baud_tick) begin
                        if (rx_tick_count == c_SAMPLE_POINT - 1) begin
                            if (rx_sync3 == 1'b0) begin // Framing error if stop bit is not high
                                UART_Error <= 1'b1;
                            end else begin
                                data_out <= rx_data_reg; // Successful reception
                            end
                        end
                        rx_tick_count <= rx_tick_count + 1;
                    end
                end
            endcase
        end
    end

    // Receiver combinational logic (state transitions)
    always_comb begin
        rx_state_next = rx_state_reg;
        case (rx_state_reg)
            RX_IDLE:      if (rx_sync2 == 1'b1 && rx_sync3 == 1'b0) rx_state_next = RX_START_BIT;
            RX_START_BIT: if (baud_tick && rx_tick_count == c_OVERSAMPLE_RATE - 1) begin
                            if (rx_sync3 == 1'b0) rx_state_next = RX_DATA_BITS;
                            else rx_state_next = RX_IDLE; // Glitch, return to idle
                          end
            RX_DATA_BITS: if (baud_tick && rx_tick_count == c_OVERSAMPLE_RATE - 1 && rx_bit_count == 7) rx_state_next = RX_STOP_BIT;
            RX_STOP_BIT:  if (baud_tick && rx_tick_count == c_OVERSAMPLE_RATE - 1) rx_state_next = RX_IDLE;
        endcase
    end

endmodule