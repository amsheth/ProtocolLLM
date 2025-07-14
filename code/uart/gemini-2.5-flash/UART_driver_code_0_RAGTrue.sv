module UART_driver #(
    parameter CLK_FREQ    = 50_000_000, // System clock frequency in Hz
    parameter BAUD_RATE   = 9600,       // Desired baud rate
    parameter DATA_BITS   = 8,          // Number of data bits (7 or 8)
    parameter STOP_BITS   = 1,          // Number of stop bits (1 or 2)
    parameter PARITY_EN   = 0,          // 0: No parity, 1: Parity enabled
    parameter PARITY_TYPE = 0           // 0: Even parity, 1: Odd parity (if PARITY_EN=1)
) (
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset

    // Transmit Interface
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    output logic       TX,         // UART transmit line
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting

    // Receive Interface
    input  logic       RX,         // UART receive line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Error  // High if framing or parity error detected
);

    // Function for GCD (Greatest Common Divisor)
    // Used for calculating fractional baud rate generator parameters
    function automatic int gcd(int a, int b);
        while (b != 0) begin
            int temp = b;
            b = a % b;
            a = temp;
        end
        return a;
    endfunction

    // Internal parameters for baud rate generation based on provided formulas
    // D_BAUD_FREQ = 16 * BaudRate / gcd(GlobalClockFreq, 16 * BaudRate)
    // D_BAUD_LIMIT = GlobalClockFreq / gcd(GlobalClockFreq, 16 * BaudRate) - D_BAUD_FREQ
    localparam int N_VAL = 16 * BAUD_RATE;
    localparam int G_VAL = gcd(CLK_FREQ, N_VAL);
    localparam int D_BAUD_FREQ_VAL = N_VAL / G_VAL;
    localparam int D_BAUD_LIMIT_VAL = CLK_FREQ / G_VAL - D_BAUD_FREQ_VAL;

    // Baud Rate Generator
    // This counter increments by D_BAUD_FREQ_VAL each clock cycle.
    // When it reaches or exceeds D_BAUD_LIMIT_VAL, a baud_tick_16x is generated,
    // and D_BAUD_LIMIT_VAL is subtracted from the counter.
    logic [31:0] baud_cnt;
    logic        baud_tick_16x; // Pulse at 16x the baud rate

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt <= 0;
            baud_tick_16x <= 0;
        end else begin
            baud_cnt <= baud_cnt + D_BAUD_FREQ_VAL;
            if (baud_cnt >= D_BAUD_LIMIT_VAL) begin
                baud_cnt <= baud_cnt - D_BAUD_LIMIT_VAL;
                baud_tick_16x <= 1;
            end else begin
                baud_tick_16x <= 0;
            end
        end
    end

    // TX Module
    typedef enum logic [2:0] {
        TX_IDLE,       // Ready to transmit, TX high
        TX_START,      // Transmitting start bit (low)
        TX_DATA,       // Transmitting data bits (LSB first)
        TX_PARITY,     // Transmitting parity bit (optional)
        TX_STOP        // Transmitting stop bit(s) (high)
    } tx_state_e;

    tx_state_e tx_state;
    logic [7:0] tx_shift_reg;   // Holds data to be transmitted
    logic [3:0] tx_bit_cnt;     // Counts bits transmitted (0 to DATA_BITS-1)
    logic [3:0] tx_baud_tick_cnt; // Counts 16x baud ticks within a bit period

    logic tx_busy_internal;
    logic tx_ready_internal;
    logic tx_out_reg; // Register for the TX line output

    assign UART_Busy  = tx_busy_internal;
    assign UART_Ready = tx_ready_internal;
    assign TX         = tx_out_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state         <= TX_IDLE;
            tx_shift_reg     <= 8'h00;
            tx_bit_cnt       <= 0;
            tx_baud_tick_cnt <= 0;
            tx_busy_internal <= 0;
            tx_ready_internal <= 1;
            tx_out_reg       <= 1'b1; // TX line is high when idle
        end else begin
            // Default to not ready, will be set high in TX_IDLE
            tx_ready_internal <= 0; 

            if (baud_tick_16x) begin
                tx_baud_tick_cnt <= tx_baud_tick_cnt + 1;
            end

            case (tx_state)
                TX_IDLE: begin
                    tx_out_reg       <= 1'b1; // Ensure TX is high
                    tx_ready_internal <= 1;   // Ready to accept new data
                    tx_busy_internal <= 0;
                    tx_baud_tick_cnt <= 0;     // Reset baud tick counter
                    if (UART_Start && tx_ready_internal) begin // Start transmission if requested and ready
                        tx_shift_reg     <= data_in;
                        tx_state         <= TX_START;
                        tx_out_reg       <= 1'b0; // Transmit start bit (low)
                        tx_busy_internal <= 1;
                        tx_baud_tick_cnt <= 0; // Start counting for the start bit
                    end
                end
                TX_START: begin
                    if (tx_baud_tick_cnt == 16) begin // After 16 ticks (1 bit period)
                        tx_state         <= TX_DATA;
                        tx_bit_cnt       <= 0;
                        tx_baud_tick_cnt <= 0;
                        tx_out_reg       <= tx_shift_reg[0]; // Transmit first data bit (LSB)
                        tx_shift_reg     <= tx_shift_reg >> 1; // Shift right for next bit
                    end
                end
                TX_DATA: begin
                    if (tx_baud_tick_cnt == 16) begin // After 16 ticks (1 bit period)
                        tx_baud_tick_cnt <= 0;
                        tx_bit_cnt       <= tx_bit_cnt + 1;
                        if (tx_bit_cnt == DATA_BITS - 1) begin // Check if last data bit was just transmitted
                            if (PARITY_EN) begin
                                tx_state <= TX_PARITY;
                                // Calculate parity: Even (XOR sum) or Odd (NOT XOR sum)
                                tx_out_reg <= (PARITY_TYPE == 0) ? ^tx_shift_reg : !^tx_shift_reg;
                            end else begin
                                tx_state <= TX_STOP;
                                tx_out_reg <= 1'b1; // Transmit stop bit (high)
                            end
                        end else begin
                            tx_out_reg   <= tx_shift_reg[0]; // Transmit next data bit
                            tx_shift_reg <= tx_shift_reg >> 1;
                        end
                    end
                end
                TX_PARITY: begin
                    if (tx_baud_tick_cnt == 16) begin // After 16 ticks (1 bit period)
                        tx_baud_tick_cnt <= 0;
                        tx_state         <= TX_STOP;
                        tx_out_reg       <= 1'b1; // Transmit stop bit (high)
                    end
                end
                TX_STOP: begin
                    // Wait for STOP_BITS periods
                    if (tx_baud_tick_cnt == (STOP_BITS * 16)) begin
                        tx_state         <= TX_IDLE;
                        tx_busy_internal <= 0;
                        tx_ready_internal <= 1; // Ready for next transmission
                    end
                end
            endcase
        end
    end

    // RX Module
    typedef enum logic [2:0] {
        RX_IDLE,         // Waiting for start bit
        RX_START_DETECT, // Detecting start bit and waiting for middle of bit
        RX_DATA,         // Receiving data bits
        RX_PARITY,       // Receiving parity bit (optional)
        RX_STOP          // Receiving stop bit(s)
    } rx_state_e;

    rx_state_e rx_state;
    logic [7:0] rx_shift_reg;   // Accumulates received data (LSB first)
    logic [3:0] rx_bit_cnt;     // Counts received bits
    logic [3:0] rx_baud_tick_cnt; // Counts 16x baud ticks within a bit period
    logic       rx_error_internal; // Internal error flag for framing or parity

    assign data_out   = rx_shift_reg;
    assign UART_Error = rx_error_internal;

    // Synchronize RX input to system clock domain to prevent metastability
    logic rx_sync_q1, rx_sync_q2;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync_q1 <= 1'b1;
            rx_sync_q2 <= 1'b1;
        end else begin
            rx_sync_q1 <= RX;
            rx_sync_q2 <= rx_sync_q1;
        end
    end
    logic rx_synced;
    assign rx_synced = rx_sync_q2; // Stable synchronized RX input

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state         <= RX_IDLE;
            rx_shift_reg     <= 8'h00;
            rx_bit_cnt       <= 0;
            rx_baud_tick_cnt <= 0;
            rx_error_internal <= 0;
        end else begin
            if (baud_tick_16x) begin
                rx_baud_tick_cnt <= rx_baud_tick_cnt + 1;
            end

            case (rx_state)
                RX_IDLE: begin
                    rx_error_internal <= 0; // Clear error flag
                    rx_baud_tick_cnt <= 0;   // Reset baud tick counter
                    if (!rx_synced) begin // Detect falling edge (start bit)
                        rx_state         <= RX_START_DETECT;
                        rx_baud_tick_cnt <= 0; // Start counting for the start bit
                    end
                end
                RX_START_DETECT: begin
                    if (rx_baud_tick_cnt == 8) begin // Sample in the middle of the start bit
                        if (!rx_synced) begin // Still low, valid start bit
                            rx_state         <= RX_DATA;
                            rx_bit_cnt       <= 0;
                            rx_baud_tick_cnt <= 0; // Reset for data bits
                        end else begin // Glitch or false start, go back to idle
                            rx_state <= RX_IDLE;
                        end
                    end
                end
                RX_DATA: begin
                    if (rx_baud_tick_cnt == 16) begin // Sample at the middle of each data bit
                        rx_baud_tick_cnt <= 0;
                        // Shift in LSB first: new bit goes to rx_shift_reg[0], existing bits shift left
                        rx_shift_reg     <= {rx_shift_reg[6:0], rx_synced}; 
                        rx_bit_cnt       <= rx_bit_cnt + 1;
                        if (rx_bit_cnt == DATA_BITS - 1) begin // Check if last data bit was just received
                            if (PARITY_EN) begin
                                rx_state <= RX_PARITY;
                            end else begin
                                rx_state <= RX_STOP;
                            end
                        end
                    end
                end
                RX_PARITY: begin
                    if (rx_baud_tick_cnt == 16) begin // Sample at the middle of the parity bit
                        rx_baud_tick_cnt <= 0;
                        rx_state         <= RX_STOP;
                        // Check parity: Even (XOR sum) or Odd (NOT XOR sum)
                        logic calculated_parity;
                        calculated_parity = (PARITY_TYPE == 0) ? ^rx_shift_reg : !^rx_shift_reg;
                        if (calculated_parity != rx_synced) begin
                            rx_error_internal <= 1; // Parity error detected
                        end
                    end
                end
                RX_STOP: begin
                    // Wait for STOP_BITS periods, sample at the middle of the last stop bit
                    if (rx_baud_tick_cnt == (STOP_BITS * 16)) begin
                        rx_baud_tick_cnt <= 0;
                        if (!rx_synced) begin // Stop bit should be high, if low, it's a framing error
                            rx_error_internal <= 1; // Framing error detected
                        end
                        rx_state <= RX_IDLE; // Return to idle, ready for next byte
                    end
                end
            endcase
        end
    end

endmodule