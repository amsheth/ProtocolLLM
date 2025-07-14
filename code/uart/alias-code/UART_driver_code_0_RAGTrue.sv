module UART_driver(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    output logic       TX,         // UART transmit line
    input  logic       RX,         // UART receive line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Parameters
    parameter CLK_FREQ = 50_000_000; // System clock frequency in Hz
    parameter BAUD_RATE = 9600;     // Desired baud rate

    // Internal signals
    logic [3:0] bit_cnt;             // Bit counter
    logic [7:0] tx_data;             // Data to be transmitted
    logic [7:0] rx_data;             // Received data
    logic tx_start;                  // Internal start signal
    logic rx_start;                  // Internal start signal
    logic tx_done;                   // Transmission done signal
    logic rx_done;                   // Reception done signal
    logic tx_error;                  // Transmission error signal
    logic rx_error;                  // Reception error signal
    logic [2:0] parity_cnt;          // Parity bit counter
    logic parity;                    // Parity bit

    // Baud rate generator
    logic [15:0] baud_cnt;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt <= 16'd0;
        end else if (baud_cnt == (CLK_FREQ / (16 * BAUD_RATE)) - 1) begin
            baud_cnt <= 16'd0;
        end else begin
            baud_cnt <= baud_cnt + 16'd1;
        end
    end

    // UART transmitter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            TX <= 1'b1;
            tx_start <= 1'b0;
            tx_data <= 8'b0;
            bit_cnt <= 4'b0;
            tx_done <= 1'b0;
            tx_error <= 1'b0;
        end else if (tx_start) begin
            if (bit_cnt == 4'd8) begin
                TX <= 1'b1;
                tx_start <= 1'b0;
                tx_done <= 1'b1;
            end else begin
                TX <= tx_data[bit_cnt];
                tx_data <= {tx_data[6:0], 1'b0};
                bit_cnt <= bit_cnt + 4'd1;
            end
        end else if (UART_Start) begin
            tx_start <= 1'b1;
            tx_data <= data_in;
            bit_cnt <= 4'b0;
            tx_done <= 1'b0;
            tx_error <= 1'b0;
        end
    end

    // UART receiver
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            RX <= 1'b1;
            rx_start <= 1'b0;
            rx_data <= 8'b0;
            bit_cnt <= 4'b0;
            rx_done <= 1'b0;
            rx_error <= 1'b0;
        end else if (rx_start) begin
            if (bit_cnt == 4'd8) begin
                RX <= 1'b1;
                rx_start <= 1'b0;
                rx_done <= 1'b1;
                data_out <= rx_data;
            end else begin
                RX <= RX;
                rx_data <= {rx_data[6:0], RX};
                bit_cnt <= bit_cnt + 4'd1;
            end
        end else if (RX == 1'b0) begin
            rx_start <= 1'b1;
            rx_data <= 8'b0;
            bit_cnt <= 4'b0;
            rx_done <= 1'b0;
            rx_error <= 1'b0;
        end
    end

    // Parity generator and checker
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            parity_cnt <= 3'b0;
            parity <= 1'b0;
        end else if (tx_start) begin
            parity_cnt <= 3'b0;
            parity <= 1'b0;
        end else if (bit_cnt == 4'd8) begin
            parity_cnt <= 3'b0;
            parity <= 1'b0;
        end else begin
            parity_cnt <= parity_cnt + 1'b1;
            parity <= parity ^ tx_data[bit_cnt];
        end
    end

    // Output logic
    assign UART_Ready = ~tx_start;
    assign UART_Busy = tx_start;
    assign UART_Error = tx_error | rx_error;

endmodule