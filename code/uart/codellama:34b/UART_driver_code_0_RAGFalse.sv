module UART_driver(
    input  logic clk,        // System clock input
    input  logic rst,        // Asynchronous reset input
    input  logic UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic RX,         // UART receive line
    output logic TX,         // UART transmit line
    output logic [7:0] data_out,   // Received data
    output logic UART_Ready, // Ready to transmit next byte
    output logic UART_Busy,  // Indicates UART is currently transmitting
    output logic UART_Error  // High if framing or parity error detected
);

    // Define the baud rate and other configuration parameters
    parameter BAUD_RATE = 115200;
    parameter DATA_WIDTH = 8;
    parameter PARITY = "NONE";
    parameter STOP_BITS = 1;

    // Internal signals
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic [2:0] tx_state;
    logic [2:0] rx_state;
    logic tx_busy;
    logic rx_busy;
    logic error;

    // Transmitter state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_data <= '0;
            tx_state <= 2'b00;
            TX <= 1'b0;
            tx_busy <= 1'b0;
        end else begin
            case (tx_state)
                2'b00: begin // Idle state
                    if (UART_Start) begin
                        tx_data <= data_in;
                        TX <= 1'b1;
                        tx_busy <= 1'b1;
                        tx_state <= 2'b01;
                    end else begin
                        tx_state <= 2'b00;
                    end
                end
                2'b01: begin // Start bit
                    if (tx_busy) begin
                        TX <= 1'b0;
                        tx_data <= {tx_data[6:0], 1'b0};
                        tx_state <= 2'b10;
                    end else begin
                        tx_state <= 2'b00;
                    end
                end
                2'b10: begin // Data bits
                    if (tx_busy) begin
                        TX <= tx_data[7];
                        tx_data <= {tx_data[6:0], 1'b0};
                        tx_state <= 2'b11;
                    end else begin
                        tx_state <= 2'b00;
                    end
                end
                2'b11: begin // Stop bit
                    if (tx_busy) begin
                        TX <= 1'b1;
                        tx_data <= '0;
                        tx_state <= 2'b00;
                        tx_busy <= 1'b0;
                    end else begin
                        tx_state <= 2'b00;
                    end
                end
            endcase
        end
    end

    // Receiver state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_data <= '0;
            rx_state <= 2'b00;
            RX <= 1'b0;
            rx_busy <= 1'b0;
        end else begin
            case (rx_state)
                2'b00: begin // Idle state
                    if (RX && !rx_busy) begin
                        rx_data <= '0;
                        rx_busy <= 1'b1;
                        rx_state <= 2'b01;
                    end else begin
                        rx_state <= 2'b00;
                    end
                end
                2'b01: begin // Start bit
                    if (rx_busy) begin
                        RX <= 1'b0;
                        rx_data <= {rx_data[6:0], 1'b0};
                        rx_state <= 2'b10;
                    end else begin
                        rx_state <= 2'b00;
                    end
                end
                2'b10: begin // Data bits
                    if (rx_busy) begin
                        RX <= rx_data[7];
                        rx_data <= {rx_data[6:0], 1'b0};
                        rx_state <= 2'b11;
                    end else begin
                        rx_state <= 2'b00;
                    end
                end
                2'b11: begin // Stop bit
                    if (rx_busy) begin
                        RX <= 1'b1;
                        rx_data <= '0;
                        rx_state <= 2'b00;
                        rx_busy <= 1'b0;
                    end else begin
                        rx_state <= 2'b00;
                    end
                end
            endcase
        end
    end

    // Output assignments
    assign UART_Ready = !tx_busy && !rx_busy;
    assign UART_Busy = tx_busy || rx_busy;
    assign UART_Error = error;
    assign data_out = rx_data;

endmodule