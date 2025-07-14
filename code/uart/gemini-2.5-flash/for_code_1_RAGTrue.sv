// SystemVerilog module for a UART (Universal Asynchronous Receiver-Transmitter) controller.
// Supports configurable baud rates, transmit and receive functionality,
// and proper start, data, parity (optional), and 2 stop bit handling.
// Operates in full-duplex mode.

module UART_driver #(
    parameter int CLK_FREQ      = 100_000_000, // System clock frequency in Hz
    parameter int BAUD_RATE     = 115200,      // Desired baud rate
    parameter int DATA_BITS     = 8,           // Number of data bits (5-9)
    parameter int PARITY_TYPE   = 0            // 0: None, 1: Even, 2: Odd
) (
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission (pulse, active high)
    input  logic [8:0] data_in,    // Data to be transmitted (LSB first, data_in[DATA_BITS-1:0] used)
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [8:0] data_out,   // Received data (data_out[DATA_BITS-1:0] valid, upper bits zeroed)
    output logic       UART_Ready, // Ready to transmit next byte (active high)
    output logic       UART_Busy,  // Indicates UART is currently transmitting (active high)
    output logic       UART_Error  // High if framing or parity error detected (sticky, cleared by rst)
);

    // Internal parameters and constants
    localparam int OVERSAMPLING_FACTOR = 16; // For RX oversampling (common value)
    localparam int NUM_STOP_BITS = 2;         // Fixed to 2 stop bits as per requirement

    // Calculate baud rate divisors
    // For 1x baud tick (TX): CLK_FREQ / BAUD_RATE
    localparam int BAUD_TICK_DIVISOR_1X = CLK_FREQ / BAUD_RATE;
    // For 16x baud tick (RX oversampling): CLK_FREQ / (BAUD_RATE * OVERSAMPLING_FACTOR)
    localparam int BAUD_TICK_DIVISOR_16X = CLK_FREQ / (BAUD_RATE * OVERSAMPLING_FACTOR);

    // Compile-time checks for parameter validity
    initial begin
        if (BAUD_TICK_DIVISOR_1X == 0) begin
            $error("UART_driver: BAUD_TICK_DIVISOR_1X is zero. CLK_FREQ must be >= BAUD_RATE.");
        end
        if (BAUD_TICK_DIVISOR_16X == 0) begin
            $error("UART_driver: BAUD_TICK_DIVISOR_16X is zero. CLK_FREQ must be >= (BAUD_RATE * OVERSAMPLING_FACTOR).");
        end
        if (DATA_BITS < 5 || DATA_BITS > 9) begin
            $error("UART_driver: DATA_BITS must be between 5 and 9.");
        end
        if (PARITY_TYPE < 0 || PARITY_TYPE > 2) begin
            $error("UART_driver: PARITY_TYPE must be 0 (None), 1 (Even), or 2 (Odd).");
        end
    end

    // Baud Rate Generator
    logic baud_tick_1x;  // Pulse at 1x baud rate for TX
    logic baud_tick_16x; // Pulse at 16x baud rate for RX oversampling

    // Counter for 1x baud tick (width handles case where divisor is 1)
    logic [($clog2(BAUD_TICK_DIVISOR_1X) == 0 ? 0 : $clog2(BAUD_TICK_DIVISOR_1X)-1):0] baud_cnt_1x;
    // Counter for 16x baud tick (width handles case where divisor is 1)
    logic [($clog2(BAUD_TICK_DIVISOR_16X) == 0 ? 0 : $clog2(BAUD_TICK_DIVISOR_16X)-1):0] baud_cnt_16x;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt_1x <= '0;
            baud_tick_1x <= 1'b0;
            baud_cnt_16x <= '0;
            baud_tick_16x <= 1'b0;
        end else begin
            // 1x Baud Tick for TX
            if (baud_cnt_1x == BAUD_TICK_DIVISOR_1X - 1) begin
                baud_cnt_1x <= '0;
                baud_tick_1x <= 1'b1;
            end else begin
                baud_cnt_1x <= baud_cnt_1x + 1;
                baud_tick_1x <= 1'b0;
            end

            // 16x Baud Tick for RX oversampling
            if (baud_cnt_16x == BAUD_TICK_DIVISOR_16X - 1) begin
                baud_cnt_16x <= '0;
                baud_tick_16x <= 1'b1;
            end else begin
                baud_cnt_16x <= baud_cnt_16x + 1;
                baud
_tick_16x <= 1'b0;
            end
        end
    end

    // TX Module
    localparam int TX_IDLE = 0, TX_START = 1, TX_DATA = 2, TX_PARITY = 3, TX_STOP = 4;
    logic [2:0] tx_state;
    logic [DATA_BITS-1:0] tx_data_reg; // Data to be transmitted
    logic tx_parity_bit;               // Calculated parity bit
    // Counter for data bits (width handles case where DATA_BITS is 1)
    logic [($clog2(DATA_BITS) == 0 ? 0 : $clog2(DATA_BITS)-1):0] tx_bit_cnt;
    // Counter for stop bits (width handles case where NUM_STOP_BITS is 1)
    logic [($clog2(NUM_STOP_BITS) == 0 ? 0 : $clog2(NUM_STOP_BITS)-1):0] tx_stop_cnt;
    logic tx_busy_internal;            // Internal busy flag
    logic tx_start_pulse;              // Edge-detected UART_Start

    // Capture UART_Start as a single-cycle pulse when not busy
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_start_pulse <= 1'b0;
        end else begin
            tx_start_pulse <= UART_Start & ~tx_busy_internal;
        end
    end

    assign UART_Busy = tx_busy_internal;
    assign UART_Ready = (tx_state == TX_IDLE); // Ready when idle

    // TX output line: default high (idle), low for start, data/parity/stop bits
    assign TX = (tx_state == TX_IDLE || tx_state == TX_STOP) ? 1'b1 :
                (tx_state == TX_START) ? 1'b0 :
                (tx_state == TX_DATA) ? tx_data_reg[0] :
                (tx_state == TX_PARITY) ? tx_parity_bit : 1'b1; // Default to high for safety

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            tx_data_reg <= '0;
            tx_bit_cnt <= '0;
            tx_stop_cnt <= '0;
            tx_busy_internal <= 1'b0;
            tx_parity_bit <= 1'b0;
        end else begin
            if (baud_tick_1x) begin // Advance state on 1x baud tick
                case (tx_state)
                    TX_IDLE: begin
                        if (tx_start_pulse) begin // Triggered by UART_Start pulse
                            tx_data_reg <= data_in[DATA_BITS-1:0]; // Load data
                            tx_state <= TX_START;
                            tx_busy_internal <= 1'b1;
                            tx_bit_cnt <= '0;
                            tx_stop_cnt <= '0;
                            // Calculate parity if enabled
                            if (PARITY_TYPE != 0) begin
                                logic parity_val;
                                parity_val = ^(data_in[DATA_BITS-1:0]); // XOR all data bits
                                if (PARITY_TYPE == 1) begin // Even parity
                                    tx_parity_bit <= parity_val;
                                end else begin // Odd parity
                                    tx_parity_bit <= ~parity_val;
                                end
                            end
                        end
                    end
                    TX_START: begin
                        tx_state <= TX_DATA; // Move to sending data bits
                    end
                    TX_DATA: begin
                        tx_data_reg <= tx_data_reg >> 1; // Shift right for next bit (LSB first)
                        if (tx_bit_cnt < DATA_BITS - 1) begin
                            tx_bit_cnt <= tx_bit_cnt + 1;
                        end else begin
                            if (PARITY_TYPE != 0) begin
                                tx_state <= TX_PARITY; // Move to sending parity bit
                            end else begin
                                tx_state <= TX_STOP; // Move to sending stop bits
                            end
                            tx_bit_cnt <= '0; // Reset for next use
                        end
                    end
                    TX_PARITY: begin
                        tx_state <= TX_STOP; // Move to sending stop bits
                    end
                    TX_STOP: begin
                        if (tx_stop_cnt < NUM_STOP_BITS - 1) begin // Count up to NUM_STOP_BITS-1 (e.g., 0 and 1 for 2 stop bits)
                            tx_stop_cnt <= tx_stop_cnt + 1;
                        end else begin
                            tx_state <= TX_IDLE; // Transmission complete
                            tx_busy_internal <= 1'b0;
                        end
                    end
                    default: tx_state <= TX_IDLE; // Should not happen, reset to idle
                endcase
            end
        end
    end

    // RX Module
    localparam int RX_IDLE = 0, RX_START = 1, RX_DATA = 2, RX_PARITY = 3, RX_STOP = 4, RX_DONE = 5;
    logic [2:0] rx_state;
    logic [DATA_BITS-1:0] rx_data_reg; // Received data
    // Counter for 16x samples within a bit period
    logic [($clog2(OVERSAMPLING_FACTOR) == 0 ? 0 : $clog2(OVERSAMPLING_FACTOR)-1):0] rx_sample_cnt;
    // Counter for received data bits
    logic [($clog2(DATA_BITS) == 0 ? 0 : $clog2(DATA_BITS)-1):0] rx_data_bit_cnt;
    // Counter for received stop bits
    logic [($clog2(NUM_STOP_BITS) == 0 ? 0 : $clog2(NUM_STOP_BITS)-1):0] rx_stop_bit_cnt;
    logic rx_parity_bit_rcvd; // The actual parity bit received
    logic rx_error_internal;  // Internal sticky error flag
    logic rx_parity_error;    // Parity error detected
    logic rx_framing_error;   // Framing error detected (start or stop bit violation)

    // Output received data, padded with zeros if DATA_BITS < 9
    assign data_out = {{(9-DATA_BITS){1'b0}}, rx_data_reg};
    assign UART_Error = rx_error_internal; // Combined error output

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_data_reg <= '0;
            rx_sample_cnt <= '0;
            rx_data_bit_cnt <= '0;
            rx_stop_bit_cnt <= '0;
            rx_error_internal <= 1'b0;
            rx_parity_error <= 1'b0;
            rx_framing_error <= 1'b0;
            rx_parity_bit_rcvd <= 1'b0;
        end else begin
            if (baud_tick_16x) begin // Advance state on 16x baud tick
                case (rx_state)
                    RX_IDLE: begin
                        if (RX == 1'b0) begin // Detect falling edge (start bit)
                            rx_state <= RX_START;
                            rx_sample_cnt <= '0; // Reset sample counter
                            rx_data_bit_cnt <= '0; // Reset data bit counter
                            rx_stop_bit_cnt <= '0; // Reset stop bit counter
                            rx_data_reg <= '0; // Clear data register
                            rx_error_internal <= 1'b0; // Clear previous errors
                            rx_parity_error <= 1'b0;
                            rx_framing_error <= 1'b0;
                        end
                    end
                    RX_START: begin
                        rx_sample_cnt <= rx_sample_cnt + 1;
                        // Sample at the middle of the start bit (8th sample of 16)
                        if (rx_sample_cnt == OVERSAMPLING_FACTOR / 2 - 1) begin
                            if (RX == 1'b0) begin // Start bit must still be low
                                rx_state <= RX_DATA;
                                rx_sample_cnt <= '0; // Reset for data bit sampling
                            end else begin // False start or glitch
                                rx_state <= RX_IDLE;
                                rx_error_internal <= 1'b1;
                                rx_framing_error <= 1'b1;
                            end
                        end
                    end
                    RX_DATA: begin
                        rx_sample_cnt <= rx_sample_cnt + 1;
                        // Sample at the middle of each data bit (16th sample of 16)
                        if (rx_sample_cnt == OVERSAMPLING_FACTOR - 1) begin
                            rx_sample_cnt <= '0;
                            // Shift in new bit (LSB first into bit 0)
                            rx_data_reg <= {rx_data_reg[DATA_BITS-2:0], RX};
                            if (rx_data_bit_cnt < DATA_BITS - 1) begin
                                rx_data_bit_cnt <= rx_data_bit_cnt + 1;
                            end else begin
                                if (PARITY_TYPE != 0) begin
                                    rx_state <= RX_PARITY; // All data bits received, check parity
                                end else begin
                                    rx_state <= RX_STOP; // All data bits received, check stop bits
                                end
                            end
                        end
                    end
                    RX_PARITY: begin
                        rx_sample_cnt <= rx_sample_cnt + 1;
                        // Sample at the middle of the parity bit
                        if (rx_sample_cnt == OVERSAMPLING_FACTOR - 1) begin
                            rx_sample_cnt <= '0;
                            rx_parity_bit_rcvd <= RX; // Store received parity bit

                            // Check parity
                            logic calculated_parity;
                            calculated_parity = ^(rx_data_reg[DATA_BITS-1:0]); // XOR of received data bits
                            if (PARITY_TYPE == 1) begin // Even parity
                                if (calculated_parity != rx_parity_bit_rcvd) begin
                                    rx_parity_error <= 1'b1;
                                    rx_error_internal <= 1'b1;
                                end
                            end else if (PARITY_TYPE == 2) begin // Odd parity
                                if (calculated_parity == rx_parity_bit_rcvd) begin
                                    rx_parity_error <= 1'b1;
                                    rx_error_internal <= 1'b1;
                                end
                            end
                            rx_state <= RX_STOP; // Move to checking stop bits
                        end
                    end
                    RX_STOP: begin
                        rx_sample_cnt <= rx_sample_cnt + 1;
                        // Sample at the middle of each stop bit
                        if (rx_sample_cnt == OVERSAMPLING_FACTOR - 1) begin
                            rx_sample_cnt <= '0;
                            if (RX == 1'b1) begin // Stop bit must be high
                                if (rx_stop_bit_cnt < NUM_STOP_BITS - 1) begin // Check for subsequent stop bits
                                    rx_stop_bit_cnt <= rx_stop_bit_cnt + 1;
                                    // Stay in RX_STOP to sample the next stop bit
                                end else begin
                                    rx_state <= RX_DONE; // All bits received successfully
                                end
                            end else begin // Framing error: stop bit was low
                                rx_framing_error <= 1'b1;
                                rx_error_internal <= 1'b1;
                                rx_state <= RX_IDLE; // Go back to idle immediately on error
                            end
                        end
                    end
                    RX_DONE: begin
                        // Data is ready, transition back to idle
                        rx_state <= RX_IDLE;
                    end
                    default: rx_state <= RX_IDLE; // Should not happen, reset to idle
                endcase
            end
        end
    end

endmodule