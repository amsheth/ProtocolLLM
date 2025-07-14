module UART_driver(
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line input
    output logic       TX,         // UART transmit line output
    output logic [7:0] data_out,   // Received data output
    output logic       UART_Ready, // Ready to transmit next byte output
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Baud rate configuration (example: 9600 baud)
    parameter BAUD_RATE = 104; // This value depends on the clock frequency
    parameter CLOCK_FREQUENCY = 50000000; // Example clock frequency in Hz
    localparam integer BAUDRATE_DIVISOR = (CLOCK_FREQUENCY / BAUD_RATE);

    enum logic {IDLE, START, DATA, PARITY, STOP} state, next_state;
    logic [7:0] shift_register;
    logic [3:0] bit_index;
    logic [9:0] baud_counter; // 16x oversampling for 8N1 configuration
    logic rx_sample;
    logic parity_bit;
    logic parity_enable;
    logic stop_bit;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            baud_counter <= 0;
            bit_index <= 0;
            shift_register <= 0;
            UART_Ready <= 1'b1;
            UART_Busy <= 1'b0;
            UART_Error <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (UART_Start) begin
                        data_out <= shift_register[7:0]; // Assuming [9:0] includes start, data, parity, stop bits
                        UART_Ready <= 1'b0;
                        UART_Busy <= 1'b1;
                        state <= START;
                    end else begin
                        state <= IDLE;
                    end
                end
                START: begin
                    if (baud_counter == BAUDRATE_DIVISOR/2) begin
                        baud_counter <= 0;
                        shift_register <= {1'b0, data_in, 1'b1}; // Start bit + data bits + stop bit
                        bit_index <= 0;
                        state <= DATA;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end
                DATA: begin
                    if (baud_counter == BAUDRATE_DIVISOR) begin
                        baud_counter <= 0;
                        bit_index <= bit_index + 1;
                        shift_register <= {rx_sample, shift_register[9:1]}; // Shift in the new bit
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                    if (bit_index == 8) state <= PARITY;
                end
                PARITY: begin
                    if (baud_counter == BAUDRATE_DIVISOR) begin
                        parity_bit = ^shift_register[7:0]; // Calculate parity bit
                        shift_register <= {1'b0, data_in, 1'b1}; // Shift in the new bit
                        state <= STOP;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end
                STOP: begin
                    if (baud_counter == BAUDRATE_DIVISOR) begin
                        UART_Ready <= 1'b1;
                        UART_Busy <= 1'b0;
                        state <= IDLE;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end
            endcase
        end
    end
endmodule