module UART_driver #(
    parameter SYS_CLK_FREQ  = 50_000_000, // System clock frequency in Hz (e.g., 50 MHz)
    parameter BAUD_RATE     = 115200,     // Desired baud rate (e.g., 9600, 115200)
    parameter DATA_BITS     = 8,          // Number of data bits (8 or 9)
    parameter PARITY_EN     = 0           // 0: No parity, 1: Even parity, 2: Odd parity
) (
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset (active high)
    input  logic       UART_Start, // Signal to initiate transmission (rising edge triggered)
    input  logic [8:0] data_in,    // Data to be transmitted (LSB at data_in[0])
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [8:0] data_out,   // Received data (LSB at data_out[0])
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // --- Internal Parameter Calculations ---
    // Baud rate divisor for TX (1x clock)
    localparam BAUD_DIV_TX = SYS_CLK_FREQ / BAUD_RATE;
    // Baud rate divisor for RX (16x oversampling clock)
    localparam BAUD_DIV_RX_16X = SYS_CLK_FREQ / (BAUD_RATE * 16);

    // --- TX (Transmitter) Logic ---
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START_BIT,
        TX_DATA_BITS,
        TX_PARITY_BIT,
        TX_STOP_BITS
    } tx_state_e;

    tx_state_e tx_state, tx_next_state;
    logic [clog2(BAUD_DIV_TX)-1:0] tx_baud_cnt; // Counter for 1x baud rate
    logic                          tx_baud_tick; // Pulse at 1x baud rate
    logic [DATA_BITS-1:0]          tx_data_reg;  // Shift register for data to transmit
    logic [3:0]                    tx_bit_cnt;   // Counter for bits transmitted
    logic                          tx_parity_bit; // Calculated parity bit
    logic                          tx_busy_internal; // Internal TX busy signal

    // UART_Start edge detection
    logic tx_start_reg;
    logic tx_start_pulse;

    // TX Baud Rate Generator (1x clock)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_baud_cnt  <= '0;
            tx_baud_tick <= 1'b0;
        end else begin
            if (tx_baud_cnt == BAUD_DIV_TX - 1) begin
                tx_baud_cnt  <= '0;
                tx_baud_tick <= 1'b1;
            end else begin
                tx_baud_cnt  <= tx_baud_cnt + 1;
                tx_baud_tick <= 1'b0;
            end
        end
    end

    // TX State Machine Registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state         <= TX_IDLE;
            TX               <= 1'b1; // TX line is high when idle
            tx_data_reg      <= '0;
            tx_bit_cnt       <= '0;
            tx_parity_bit    <= 1'b0;
            tx_busy_internal <= 1'b0;
            tx_start_reg     <= 1'b0;
        end else begin
            tx_start_reg <= UART_Start; // Register UART_Start for edge detection
            tx_start_pulse <= (UART_Start && !tx_start_reg); // Detect rising edge

            tx_state <= tx_next_state;

            case (tx_state)
                TX_IDLE: begin
                    TX               <= 1'b1; // Keep TX high
                    tx_busy_internal <= 1'b0; // Not busy
                    tx_bit_cnt       <= '0;
                    if (tx_start_pulse) begin
                        tx_data_reg      <= data_in[DATA_BITS-1:0]; // Load data
                        // Calculate parity if enabled
                        if (PARITY_EN != 0) begin
                            logic parity_calc;
                            parity_calc = ^data_in[DATA_BITS-1:0]; // XOR all data bits
                            if (PARITY_EN == 1) tx_parity_bit = parity_calc; // Even parity
                            else if (PARITY_EN == 2) tx_parity_bit = !parity_calc; // Odd parity
                        end else begin
                            tx_parity_bit = 1'b0; // Not used
                        end
                        tx_busy_internal <= 1'b1; // Start transmission
                    end
                end
                TX_START_BIT: begin
                    TX <= 1'b0; // Start bit is low
                    if (tx_baud_tick) begin
                        tx_bit_cnt <= '0; // Reset bit counter for data bits
                    end
                end
                TX_DATA_BITS: begin
                    TX <= tx_data_reg[0]; // Send LSB first
                    if (tx_baud_tick) begin
                        tx_data_reg <= tx_data_reg >> 1; // Shift data right
                        tx_bit_cnt  <= tx_bit_cnt + 1;
                    end
                end
                TX_PARITY_BIT: begin
                    TX <= tx_parity_bit;
                    // No shift, just wait for tick to move to next state
                end
                TX_STOP_BITS: begin
                    TX <= 1'b1; // Stop bits are high
                    if (tx_baud_tick) begin
                        tx_bit_cnt <= tx_bit_cnt + 1;
                    end
                end
            endcase
        end
    end

    // TX Next State Logic
    always_comb begin
        tx_next_state = tx_state;
        case (tx_state)
            TX_IDLE: begin
                if (tx_start_pulse) begin
                    tx_next_state = TX_START_BIT;
                end
            end
            TX_START_BIT: begin
                if (tx_baud_tick) begin
                    tx_next_state = TX_DATA_BITS;
                end
            end
            TX_DATA_BITS: begin
                if (tx_baud_tick) begin
                    if (tx_bit_cnt == DATA_BITS - 1) begin
                        if (PARITY_EN != 0) tx_next_state = TX_PARITY_BIT;
                        else                tx_next_state = TX_STOP_BITS;
                    end
                end
            end
            TX_PARITY_BIT: begin
                if (tx_baud_tick) begin
                    tx_next_state = TX_STOP_BITS;
                end
            end
            TX_STOP_BITS: begin
                if (tx_baud_tick) begin
                    if (tx_bit_cnt == 2 - 1) begin // Always 2 stop bits
                        tx_next_state = TX_IDLE;
                    end
                end
            end
        endcase
    end

    // --- RX (Receiver) Logic ---
    typedef enum logic [3:0] {
        RX_IDLE,
        RX_START_BIT_DETECT, // Wait for falling edge on RX
        RX_START_BIT_SAMPLE, // Sample middle of start bit
        RX_DATA_BITS,
        RX_PARITY_BIT,
        RX_STOP_BITS_1,      // Sample first stop bit
        RX_STOP_BITS_2,      // Sample second stop bit
        RX_ERROR_STATE       // Hold error state
    } rx_state_e;

    rx_state_e rx_state, rx_next_state;
    logic [clog2(BAUD_DIV_RX_16X)-1:0] rx_sample_cnt; // Counter for 16x samples within a bit
    logic                              rx_bit_tick;   // Pulse at the middle of each bit for sampling
    logic [DATA_BITS-1:0]              rx_data_reg;   // Shift register for received data
    logic [3:0]                        rx_bit_cnt;    // Counter for bits received
    logic                              rx_parity_bit_expected; // Expected parity bit
    logic                              rx_error_internal; // Internal RX error signal

    // RX Input Synchronizer (2-flop synchronizer)
    logic RX_sync_0, RX_sync_1;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            RX_sync_0 <= 1'b1;
            RX_sync_1 <= 1'b1;
        end else begin
            RX_sync_0 <= RX;
            RX_sync_1 <= RX_sync_0;
        end
    end

    // RX Sample Counter and Bit Tick Generator
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sample_cnt <= '0;
            rx_bit_tick   <= 1'b0;
        end else begin
            rx_bit_tick <= 1'b0; // Default to low

            case (rx_state)
                RX_IDLE: begin
                    rx_sample_cnt <= '0; // Reset counter
                end
                RX_START_BIT_DETECT: begin
                    // If RX_sync_1 goes low, reset counter to start timing for sample
                    if (!RX_sync_1) begin
                        rx_sample_cnt <= '0;
                    end else begin
                        rx_sample_cnt <= '0; // Stay reset if RX is high
                    end
                end
                RX_START_BIT_SAMPLE, RX_DATA_BITS, RX_PARITY_BIT, RX_STOP_BITS_1, RX_STOP_BITS_2: begin
                    if (rx_sample_cnt == BAUD_DIV_RX_16X - 1) begin
                        rx_sample_cnt <= '0;
                    end else begin
                        rx_sample_cnt <= rx_sample_cnt + 1;
                    end
                    // Generate rx_bit_tick at the middle of the bit for sampling
                    if (rx_sample_cnt == (BAUD_DIV_RX_16X / 2) - 1) begin
                        rx_bit_tick <= 1'b1; // This is the actual sample point
                    end
                end
                default: begin
                    rx_sample_cnt <= '0;
                end
            endcase
        end
    end

    // RX State Machine Registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state          <= RX_IDLE;
            data_out          <= '0;
            rx_data_reg       <= '0;
            rx_bit_cnt        <= '0;
            rx_error_internal <= 1'b0;
        end else begin
            rx_state <= rx_next_state;

            case (rx_state)
                RX_IDLE: begin
                    rx_error_internal <= 1'b0; // Clear error when idle
                    rx_bit_cnt        <= '0;
                    rx_data_reg       <= '0;
                end
                RX_START_BIT_DETECT: begin
                    // State to detect falling edge and prepare for sampling
                end
                RX_START_BIT_SAMPLE: begin
                    if (rx_bit_tick) begin // Sample at middle of start bit
                        if (RX_sync_1 == 1'b0) begin // Valid start bit (still low)
                            rx_bit_cnt <= '0; // Reset bit counter for data bits
                        end else begin // Not low, error or glitch
                            rx_error_internal <= 1'b1; // Framing error
                        end
                    end
                end
                RX_DATA_BITS: begin
                    if (rx_bit_tick) begin // Sample at middle of data bit
                        // Shift in new bit (LSB first into rx_data_reg[0])
                        rx_data_reg <= {rx_data_reg[DATA_BITS-2:0], RX_sync_1};
                        rx_bit_cnt  <= rx_bit_cnt + 1;
                    end
                end
                RX_PARITY_BIT: begin
                    if (rx_bit_tick) begin // Sample at middle of parity bit
                        logic parity_calc;
                        parity_calc = ^rx_data_reg; // XOR all received data bits
                        if (PARITY_EN == 1) rx_parity_bit_expected = parity_calc; // Even parity
                        else if (PARITY_EN == 2) rx_parity_bit_expected = !parity_calc; // Odd parity
                        // If PARITY_EN is 0, this state is skipped, so no need for 'else'
                        
                        if (PARITY_EN != 0 && RX_sync_1 != rx_parity_bit_expected) begin
                            rx_error_internal <= 1'b1; // Parity error
                        end
                    end
                end
                RX_STOP_BITS_1: begin
                    if (rx_bit_tick) begin // Sample at middle of first stop bit
                        if (RX_sync_1 == 1'b1) begin // Stop bit must be high
                            // OK
                        end else begin
                            rx_error_internal <= 1'b1; // Framing error
                        end
                    end
                end
                RX_STOP_BITS_2: begin
                    if (rx_bit_tick) begin // Sample at middle of second stop bit
                        if (RX_sync_1 == 1'b1) begin // Stop bit must be high
                            // OK
                        end else begin
                            rx_error_internal <= 1'b1; // Framing error
                        end
                        // Data is ready after the last stop bit is sampled, if no error
                        if (!rx_error_internal) begin
                            data_out <= rx_data_reg; // Assign received data
                        end
                    end
                end
                RX_ERROR_STATE: begin
                    // Stay in error state until RX line goes high (idle)
                end
            endcase
        end
    end

    // RX Next State Logic
    always_comb begin
        rx_next_state = rx_state;
        case (rx_state)
            RX_IDLE: begin
                if (!RX_sync_1) begin // Detect falling edge (RX_sync_1 was high, now low)
                    rx_next_state = RX_START_BIT_DETECT; // Go to state to wait for sample point
                end
            end
            RX_START_BIT_DETECT: begin
                // Wait for the sample counter to reach the middle of the start bit
                if (rx_sample_cnt == (BAUD_DIV_RX_16X / 2) - 1) begin
                    rx_next_state = RX_START_BIT_SAMPLE;
                end
            end
            RX_START_BIT_SAMPLE: begin
                if (rx_bit_tick) begin // Sampled middle of start bit
                    if (RX_sync_1 == 1'b0) begin // Still low, valid start bit
                        rx_next_state = RX_DATA_BITS;
                    end else begin // Not low, error or glitch
                        rx_next_state = RX_ERROR_STATE; // Go to error state
                    end
                end
            end
            RX_DATA_BITS: begin
                if (rx_bit_tick) begin
                    if (rx_bit_cnt == DATA_BITS - 1) begin
                        if (PARITY_EN != 0) rx_next_state = RX_PARITY_BIT;
                        else                rx_next_state = RX_STOP_BITS_1;
                    end
                end
            end
            RX_PARITY_BIT: begin
                if (rx_bit_tick) begin
                    rx_next_state = RX_STOP_BITS_1;
                end
            end
            RX_STOP_BITS_1: begin
                if (rx_bit_tick) begin
                    rx_next_state = RX_STOP_BITS_2;
                end
            end
            RX_STOP_BITS_2: begin
                if (rx_bit_tick) begin
                    if (rx_error_internal) begin // If error occurred during reception
                        rx_next_state = RX_ERROR_STATE;
                    end else begin
                        rx_next_state = RX_IDLE; // Go back to idle
                    end
                end
            end
            RX_ERROR_STATE: begin
                // Stay in error state until RX goes high (idle)
                if (RX_sync_1 == 1'b1) begin // Line is idle
                    rx_next_state = RX_IDLE;
                end
            end
        endcase
    end

    // --- Output Assignments ---
    assign UART_Busy  = tx_busy_internal;
    assign UART_Ready = !tx_busy_internal;
    assign UART_Error = rx_error_internal;

endmodule