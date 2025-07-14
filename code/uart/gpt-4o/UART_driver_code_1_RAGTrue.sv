module UART_driver(
    input logic       clk,        // System clock
    input logic       rst,        // Asynchronous reset
    input logic       UART_Start, // Signal to initiate transmission
    input logic [8:0] data_in,    // Data to be transmitted
    input logic       RX,         // UART receive line
    output logic      TX,         // UART transmit line
    output logic [8:0] data_out,  // Received data
    output logic      UART_Ready, // Ready to transmit next byte
    output logic      UART_Busy,  // Indicates UART is currently transmitting
    output logic      UART_Error  // High if framing or parity error detected
);

    // Parameters for baud rate and states
    parameter integer BAUD_RATE_DIVIDER = 104; // Example for 9600 baud with a 1MHz clock
    parameter logic[2:0] IDLE = 3'b000, START = 3'b001, DATA = 3'b010, PARITY = 3'b011, STOP = 3'b100, CLEANUP = 3'b101;
    
    // Internal signals
    logic [7:0] transmit_buffer;
    logic [3:0] bit_counter;
    logic [3:0] baud_counter;
    logic [2:0] tx_state;
    logic [2:0] rx_state;
    logic parity_bit;
    
    // Initialization
    initial begin
        TX <= 1'b1;
        UART_Ready <= 1'b1;
        UART_Busy <= 1'b0;
        UART_Error <= 1'b0;
        tx_state <= IDLE;
        rx_state <= IDLE;
    end

    // Transmit logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            TX <= 1'b1;
            UART_Ready <= 1'b1;
            UART_Busy <= 1'b0;
            tx_state <= IDLE;
            baud_counter <= 0;
        end else begin
            case (tx_state)
                IDLE: begin
                    if (UART_Start && UART_Ready) begin
                        transmit_buffer <= data_in[7:0];
                        parity_bit <= ^data_in[7:0]; // odd parity calculation
                        UART_Ready <= 1'b0;
                        UART_Busy <= 1'b1;
                        bit_counter <= 4'd0;
                        tx_state <= START;
                    end
                end
                START: begin
                    if (baud_counter == BAUD_RATE_DIVIDER - 1) begin
                        TX <= 1'b0; // Start bit
                        baud_counter <= 0;
                        tx_state <= DATA;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end
                DATA: begin
                    if (baud_counter == BAUD_RATE_DIVIDER - 1) begin
                        TX <= transmit_buffer[bit_counter];
                        baud_counter <= 0;
                        bit_counter <= bit_counter + 1;
                        if (bit_counter == 4'd7) begin
                            tx_state <= PARITY;
                        end
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end
                PARITY: begin
                    if (baud_counter == BAUD_RATE_DIVIDER - 1) begin
                        TX <= parity_bit; // Parity bit
                        baud_counter <= 0;
                        tx_state <= STOP;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end
                STOP: begin
                    if (baud_counter == BAUD_RATE_DIVIDER - 1) begin
                        TX <= 1'b1; // Stop bit
                        baud_counter <= 0;
                        tx_state <= CLEANUP;
                    end else begin
                        baud_counter <= baud_counter + 1;
                    end
                end
                CLEANUP: begin
                    UART_Ready <= 1'b1;
                    UART_Busy <= 1'b0;
                    tx_state <= IDLE;
                end
            endcase
        end
    end

    // For brevity, receive logic and error handling are not fully implemented in this example.

endmodule