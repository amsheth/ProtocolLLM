module UART_driver(
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Parameters for UART configuration
    parameter int BAUD_RATE = 9600; // Baud rate
    parameter int CLK_FREQ = 50000000; // System clock frequency in Hz

    // Internal signals
    logic [15:0] baud_divider; // Baud rate divider
    logic [3:0] bit_counter; // Bit counter for transmission/reception
    logic [7:0] tx_shift_reg; // Shift register for transmission
    logic [7:0] rx_shift_reg; // Shift register for reception
    logic tx_start; // Start transmission
    logic rx_start; // Start reception
    logic tx_done; // Transmission done
    logic rx_done; // Reception done
    logic tx_busy; // Transmission busy
    logic rx_busy; // Reception busy
    logic parity_bit; // Parity bit
    logic parity_error; // Parity error flag
    logic framing_error; // Framing error flag

    // Baud rate divider calculation
    assign baud_divider = CLK_FREQ / BAUD_RATE;

    // UART transmitter
    UART_TX #(.BAUD_RATE(BAUD_RATE), .CLK_FREQ(CLK_FREQ))
    uart_tx_inst (
        .clk(clk),
        .rst(rst),
        .start(tx_start),
        .data_in(tx_shift_reg),
        .tx(TX),
        .done(tx_done),
        .busy(tx_busy)
    );

    // UART receiver
    UART_RX #(.BAUD_RATE(BAUD_RATE), .CLK_FREQ(CLK_FREQ))
    uart_rx_inst (
        .clk(clk),
        .rst(rst),
        .rx(RX),
        .data_out(rx_shift_reg),
        .done(rx_done),
        .busy(rx_busy),
        .parity_error(parity_error),
        .framing_error(framing_error)
    );

    // UART control logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            UART_Ready <= 1'b1;
            UART_Busy <= 1'b0;
            UART_Error <= 1'b0;
            bit_counter <= 4'b0000;
            tx_start <= 1'b0;
            tx_shift_reg <= 8'b00000000;
        end else begin
            // Transmission control
            if (UART_Start && UART_Ready && !tx_busy) begin
                UART_Ready <= 1'b0;
                UART_Busy <= 1'b1;
                tx_start <= 1'b1;
                tx_shift_reg <= data_in;
            end else if (tx_done) begin
                UART_Ready <= 1'b1;
                UART_Busy <= 1'b0;
                tx_start <= 1'b0;
            end else begin
                tx_start <= 1'b0;
            end

            // Reception control
            if (rx_done) begin
                data_out <= rx_shift_reg;
                UART_Error <= parity_error | framing_error;
            end
        end
    end

endmodule