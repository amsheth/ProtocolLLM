module UART_driver #(
    parameter CLK_FREQ    = 50_000_000, // System clock frequency in Hz (e.g., 50 MHz)
    parameter BAUD_RATE   = 115200,     // Desired baud rate (e.g., 115200 bps)
    parameter PARITY_EN   = 0,          // 0: No parity, 1: Parity enabled
    parameter PARITY_TYPE = 0,          // 0: Even parity, 1: Odd parity (if PARITY_EN = 1)
    parameter STOP_BITS   = 1           // 1: One stop bit, 2: Two stop bits
) (
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset (active high)
    input  logic       UART_Start, // Signal to initiate transmission (rising edge)
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Calculate baud rate divisor
    localparam BAUD_DIVISOR = CLK_FREQ / BAUD_RATE;
    localparam BAUD_DIVISOR_HALF = BAUD_DIVISOR / 2;

    // Check for valid baud rate divisor
    initial begin
        if (BAUD_DIVISOR < 16) begin // A common rule of thumb for reliable sampling (at least 8-16 samples per bit)
            $error("BAUD_DIVISOR is too small for reliable UART operation. Increase CLK_FREQ or decrease BAUD_RATE.");
        end
    end

    // Internal signals for TX
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP
    } tx_state_t;

    tx_state_t tx_state_reg, tx_state_next;
    logic [7:0] tx_data_shift_reg;
    logic [3:0] tx_bit_count; // 0-7 for data, 8 for parity, 9 for stop1, 10 for stop2
    logic [$clog2(BAUD_DIVISOR)-1:0] tx_baud_count;
    logic tx_parity_bit;
    logic tx_busy_internal; // Internal busy signal for TX
    logic tx_ready_internal; // Internal ready signal for TX

    // UART_Start edge detection for TX trigger
    logic uart_start_sync_1, uart_start_sync_2;
    logic uart_start_pulse;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_start_sync_1 <= 1'b0;
            uart_start_sync_2 <= 1'b0;
        end else begin
            uart_start_sync_1 <= UART_Start;
            uart_start_sync_2 <= uart_start_sync_1;
        end
    end
    assign uart_start_pulse = uart_start_sync_1 && ~uart_start_sync_2; // Rising edge detector

    // Internal signals for RX
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP
    } rx_state_t;

    rx_state_t rx_state_reg, rx_state_next;
    logic [7:0] rx_data_shift_reg;
    logic [3:0] rx_bit_count;
    logic [$clog2(BAUD_DIVISOR)-1:0] rx_baud_count;
    logic rx_sync_reg_1, rx_sync_reg_2; // For input synchronization
    logic rx_start_edge; // Detects falling edge for start bit
    logic rx_parity_calc;
    logic rx_error_internal; // Internal error signal for RX
    logic rx_data_valid; // Indicates new data is available
    logic [7:0] data_out_reg; // Register to hold received data before output

    // Output assignments
    assign UART_Busy  = tx_busy_internal;
    assign UART_Ready = tx_ready_internal;
    assign UART_Error = rx_error_internal;
    assign data_out   = data_out_reg; // Assign from register

    // Synchronize RX input
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync_reg_1 <= 1'b1; // Default to high (idle)
            rx_sync_reg_2 <= 1'b1;
        end else begin
            rx_sync_reg_1 <= RX;
            rx_sync_reg_2 <= rx_sync_reg_1;
        end
    end

    // Detect falling edge on synchronized RX for start bit
    assign rx_start_edge = (~rx_sync_reg_2) && rx_sync_reg_1; // rx_sync_reg_1 is current, rx_sync_reg_2 is previous

    // =====================================================================
    // Transmit (TX) Logic
    // =====================================================================

    // TX State Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state_reg <= TX_IDLE;
        end else begin
            tx_state_reg <= tx_state_next;
        end
    end

    // TX Next State Logic and Output Logic
    always_comb begin
        tx_state_next = tx_state_reg;
        TX = 1'b1; // Default to high (idle state)
        tx_busy_internal = 1'b0;
        tx_ready_internal = 1'b1; // Default ready

        // Default values for counters and registers (keep current values)
        tx_baud_count = tx_baud_count;
        tx_bit_count = tx_bit_count;
        tx_data_shift_reg = tx_data_shift_reg;
        tx_parity_bit = tx_parity_bit;

        case (tx_state_reg)
            TX_IDLE: begin
                TX = 1'b1; // Idle high
                tx_busy_internal = 1'b0;
                tx_ready_internal = 1'b1;
                tx_baud_count = '0; // Reset baud counter
                tx_bit_count = '0;  // Reset bit counter

                if (uart_start_pulse) begin // Trigger on rising edge of UART_Start
                    tx_state_next = TX_START;
                    tx_data_shift_reg = data_in; // Load data for transmission
                    // Calculate parity for data_in
                    if (PARITY_EN) begin
                        logic parity_sum = 1'b0;
                        for (int i = 0; i < 8; i++) begin
                            parity_sum = parity_
sum ^ data_in[i];
                        end
                        tx_parity_bit = (PARITY_TYPE == 0) ? parity_sum : ~parity_sum; // Even or Odd
                    end else begin
                        tx_parity_bit = 1'b0; // Not used if parity disabled
                    end
                end
            end

            TX_START: begin
                TX = 1'b0; // Start bit (low)
                tx_busy_internal = 1'b1;
                tx_ready_internal = 1'b0; // Not ready during transmission

                if (tx_baud_count == BAUD_DIVISOR - 1) begin
                    tx_baud_count = '0;
                    tx_state_next = TX_DATA;
                    tx_bit_count = '0; // Reset for data bits
                end else begin
                    tx_baud_count = tx_baud_count + 1;
                end
            end

            TX_DATA: begin
                TX = tx_data_shift_reg[0]; // Transmit LSB first
                tx_busy_internal = 1'b1;
                tx_ready_internal = 1'b0;

                if (tx_baud_count == BAUD_DIVISOR - 1) begin
                    tx_baud_count = '0;
                    tx_data_shift_reg = tx_data_shift_reg >> 1; // Shift right for next bit
                    if (tx_bit_count == 7) begin // All 8 data bits sent
                        if (PARITY_EN) begin
                            tx_state_next = TX_PARITY;
                        end else begin
                            tx_state_next = TX_STOP;
                            tx_bit_count = '0; // Reset for stop bits
                        end
                    end else begin
                        tx_bit_count = tx_bit_count + 1;
                    end
                end else begin
                    tx_baud_count = tx_baud_count + 1;
                end
            end

            TX_PARITY: begin
                TX = tx_parity_bit; // Transmit parity bit
                tx_busy_internal = 1'b1;
                tx_ready_internal = 1'b0;

                if (tx_baud_count == BAUD_DIVISOR - 1) begin
                    tx_baud_count = '0;
                    tx_state_next = TX_STOP;
                    tx_bit_count = '0; // Reset for stop bits
                end else begin
                    tx_baud_count = tx_baud_count + 1;
                end
            end

            TX_STOP: begin
                TX = 1'b1; // Stop bit (high)
                tx_busy_internal = 1'b1;
                tx_ready_internal = 1'b0;

                if (tx_baud_count == BAUD_DIVISOR - 1) begin
                    tx_baud_count = '0;
                    if (tx_bit_count == STOP_BITS - 1) begin // All stop bits sent
                        tx_state_next = TX_IDLE;
                    end else begin
                        tx_bit_count = tx_bit_count + 1;
                    end
                end else begin
                    tx_baud_count = tx_baud_count + 1;
                end
            end

            default: begin
                tx_state_next = TX_IDLE; // Should not happen
            end
        endcase
    end

    // =====================================================================
    // Receive (RX) Logic
    // =====================================================================

    // RX State Register and Output Data Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state_reg <= RX_IDLE;
            rx_error_internal <= 1'b0;
            rx_data_valid <= 1'b0;
            data_out_reg <= '0;
        end else begin
            rx_state_reg <= rx_state_next;
            // Clear error on new reception attempt (entering IDLE from non-IDLE)
            // or if a new start bit is detected while in IDLE
            if ((rx_state_next == RX_IDLE && rx_state_reg != RX_IDLE) || (rx_state_reg == RX_IDLE && rx_start_edge)) begin
                rx_error_internal <= 1'b0;
            end
            if (rx_data_valid) begin
                // Reverse the bits of rx_data_shift_reg for data_out_reg
                // rx_data_shift_reg has LSB at bit 7, MSB at bit 0 (due to shifting in MSB first)
                // We want data_out_reg[0] to be LSB, data_out_reg[7] to be MSB
                for (int i = 0; i < 8; i++) begin
                    data_out_reg[i] <= rx_data_shift_reg[7-i];
                end
                rx_data_valid <= 1'b0; // Clear data valid after one cycle
            end
        end
    end

    // RX Next State Logic and Data Capture
    always_comb begin
        rx_state_next = rx_state_reg;
        rx_baud_count = rx_baud_count;
        rx_bit_count = rx_bit_count;
        rx_data_shift_reg = rx_data_shift_reg;
        rx_parity_calc = rx_parity_calc;

        case (rx_state_reg)
            RX_IDLE: begin
                rx_baud_count = '0;
                rx_bit_count = '0;
                rx_data_shift_reg = '0;

                if (rx_start_edge) begin // Detect falling edge for start bit
                    rx_state_next = RX_START;
                end
            end

            RX_START: begin
                if (rx_baud_count == BAUD_DIVISOR_HALF - 1) begin // Sample in the middle of the start bit
                    if (rx_sync_reg_2 == 1'b1) begin // Should be low, if high, it's a false start
                        rx_error_internal = 1'b1;
                        rx_state_next = RX_IDLE; // Go back to idle immediately
                    end
                end

                if (rx_baud_count == BAUD_DIVISOR - 1) begin // End of start bit period
                    rx_baud_count = '0; // Reset for next bit
                    rx_state_next = RX_DATA;
                    rx_bit_count = '0;
                end else begin
                    rx_baud_count = rx_baud_count + 1;
                end
            end

            RX_DATA: begin
                if (rx_baud_count == BAUD_DIVISOR_HALF - 1) begin // Sample in the middle of the data bit
                    rx_data_shift_reg = {rx_sync_reg_2, rx_data_shift_reg[7:1]}; // Shift in new bit (MSB first)
                end

                if (rx_baud_count == BAUD_DIVISOR - 1) begin // End of data bit period
                    rx_baud_count = '0; // Reset for next bit
                    if (rx_bit_count == 7) begin // All 8 data bits received
                        if (PARITY_EN) begin
                            rx_state_next = RX_PARITY;
                            // Calculate parity for received data
                            logic parity_sum = 1'b0;
                            for (int i = 0; i < 8; i++) begin
                                parity_sum = parity_sum ^ rx_data_shift_reg[i];
                            end
                            rx_parity_calc = (PARITY_TYPE == 0) ? parity_sum : ~parity_sum; // Even or Odd
                        end else begin
                            rx_state_next = RX_STOP;
                            rx_bit_count = '0; // Reset for stop bits
                        end
                    end else begin
                        rx_bit_count = rx_bit_count + 1;
                    end
                end else begin
                    rx_baud_count = rx_baud_count + 1;
                end
            end

            RX_PARITY: begin
                if (rx_baud_count == BAUD_DIVISOR_HALF - 1) begin // Sample parity bit
                    if (PARITY_EN && (rx_sync_reg_2 != rx_parity_calc)) begin // Check only if parity is enabled
                        rx_error_internal = 1'b1; // Parity error
                    end
                end

                if (rx_baud_count == BAUD_DIVISOR - 1) begin // End of parity bit period
                    rx_baud_count = '0;
                    rx_state_next = RX_STOP;
                    rx_bit_count = '0; // Reset for stop bits
                end else begin
                    rx_baud_count = rx_baud_count + 1;
                end
            end

            RX_STOP: begin
                if (rx_baud_count == BAUD_DIVISOR_HALF - 1) begin // Sample stop bit
                    if (rx_sync_reg_2 == 1'b0) begin // Stop bit must be high, if low, it's a framing error
                        rx_error_internal = 1'b1;
                    end
                end

                if (rx_baud_count == BAUD_DIVISOR - 1) begin // End of stop bit period
                    rx_baud_count = '0;
                    if (rx_bit_count == STOP_BITS - 1) begin // All stop bits received
                        rx_state_next = RX_IDLE;
                        rx_data_valid = 1'b1; // Indicate new data is ready
                    end else begin
                        rx_bit_count = rx_bit_count + 1;
                    end
                end else begin
                    rx_baud_count = rx_baud_count + 1;
                end
            end

            default: begin
                rx_state_next = RX_IDLE;
            end
        endcase
    end

endmodule