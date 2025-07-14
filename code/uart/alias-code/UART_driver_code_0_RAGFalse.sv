module UART_driver(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Parameters
    parameter BAUD_RATE = 9600; // Default baud rate
    parameter CLK_FREQ = 50_000_000; // System clock frequency

    // Internal signals
    logic [31:0] baud_count;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic tx_start;
    logic rx_start;
    logic tx_done;
    logic rx_done;
    logic tx_error;
    logic rx_error;
    logic [2:0] bit_count;
    logic [2:0] rx_bit_count;
    logic [1:0] parity;
    logic parity_error;

    // Baud rate generator
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_count <= 32'h0;
        end else if (baud_count == (CLK_FREQ / (16 * BAUD_RATE)) - 1) begin
            baud_count <= 32'h0;
        end else begin
            baud_count <= baud_count + 1;
        end
    end

    // Transmit logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_data <= 8'h0;
            tx_start <= 1'b0;
            tx_done <= 1'b0;
            tx_error <= 1'b0;
            bit_count <= 3'b0;
        end else if (UART_Start) begin
            tx_data <= data_in;
            tx_start <= 1'b1;
            tx_done <= 1'b0;
            tx_error <= 1'b0;
            bit_count <= 3'b0;
        end else if (tx_start && baud_count == (CLK_FREQ / (16 * BAUD_RATE)) - 1) begin
            if (bit_count < 8) begin
                TX <= tx_data[bit_count];
                tx_data <= {tx_data[6:0], 1'b0};
                bit_count <= bit_count + 1;
            end else begin
                TX <= 1'b1;
                tx_start <= 1'b0;
                tx_done <= 1'b1;
            end
        end
    end

    // Receive logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_data <= 8'h0;
            rx_start <= 1'b0;
            rx_done <= 1'b0;
            rx_error <= 1'b0;
            rx_bit_count <= 3'b0;
        end else if (RX == 1'b0 && baud_count == (CLK_FREQ / (16 * BAUD_RATE)) - 1) begin
            if (rx_bit_count < 8) begin
                rx_data <= {rx_data[6:0], RX};
                rx_bit_count <= rx_bit_count + 1;
            end else begin
                rx_data <= {rx_data[6:0], RX};
                rx_start <= 1'b1;
                rx_done <= 1'b0;
                rx_bit_count <= 3'b0;
            end
        end else if (rx_start && baud_count == (CLK_FREQ / (16 * BAUD_RATE)) - 1) begin
            if (rx_bit_count < 8) begin
                rx_data <= {rx_data[6:0], RX};
                rx_bit_count <= rx_bit_count + 1;
            end else begin
                rx_data <= {rx_data[6:0], RX};
                rx_start <= 1'b0;
                rx_done <= 1'b1;
            end
        end
    end

    // Parity logic
    always_comb begin
        parity = 2'b00;
        for (int i = 0; i < 8; i++) begin
            parity = parity ^ rx_data[i];
        end
    end

    // Error detection
    always_comb begin
        if (rx_done) begin
            if (RX != 1'b1) begin
                rx_error = 1'b1;
            end else if (parity != parity_error) begin
                rx_error = 1'b1;
            end else begin
                rx_error = 1'b0;
            end
        end else begin
            rx_error = 1'b0;
        end
    end

    // Output logic
    assign UART_Ready = !tx_start && !rx_start;
    assign UART_Busy = tx_start || rx_start;
    assign UART_Error = rx_error;
    assign data_out = rx_data;

endmodule