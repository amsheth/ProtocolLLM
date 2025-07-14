module UART_driver (
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,   // Data to be transmitted (8-bit)
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,  // Received data (8-bit)
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing error detected
);

// Parameters for configuration
parameter BAUD_RATE = 9600;
parameter CLK_FREQ  = 50_000_000; // Assuming a 50 MHz clock
localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;

// Internal states and counters
typedef enum logic [2:0] {
    IDLE,
    START,
    DATA_TX,
    STOP1,
    STOP2,
    DATA_RX,
    WAIT_STOP
} state_t;

state_t tx_state, rx_state;
logic [3:0] bit_cnt;
logic [7:0] shift_reg;
logic       start_sampled;
logic       tx_start_reg;

// Baud rate generator
logic [31:0] baud_cnt;
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        baud_cnt <= 0;
    else if (baud_cnt == BIT_PERIOD - 1)
        baud_cnt <= 0;
    else
        baud_cnt <= baud_cnt + 1;
end

// Transmitter state machine
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        tx_state <= IDLE;
        bit_cnt <= 4'd0;
        TX <= 1'b1; // Idle high for UART
        tx_start_reg <= 1'b0;
    end else begin
        case (tx_state)
            IDLE: begin
                if (UART_Start) begin
                    tx_start_reg <= 1'b1;
                    bit_cnt <= 4'd0;
                    shift_reg <= data_in;
                    tx_state <= START;
                end
            end
            START: begin
                TX <= 1'b0; // Start bit is low
                if (baud_cnt == BIT_PERIOD - 1) begin
                    bit_cnt <= bit_cnt + 4'd1;
                    tx_state <= DATA_TX;
                end
            end
            DATA_TX: begin
                TX <= shift_reg[bit_cnt];
                if (baud_cnt == BIT_PERIOD - 1 && bit_cnt < 7) begin
                    bit_cnt <= bit_cnt + 4'd1;
                end else if (baud_cnt == BIT_PERIOD - 1 && bit_cnt == 7) begin
                    bit_cnt <= 4'd0;
                    tx_state <= STOP1;
                end
            end
            STOP1: begin
                TX <= 1'b1; // Stop bits are high
                if (baud_cnt == BIT_PERIOD - 1)
                    tx_state <= STOP2;
            end
            STOP2: begin
                TX <= 1'b1; // Second stop bit is also high
                if (baud_cnt == BIT_PERIOD - 1) begin
                    tx_start_reg <= 1'b0;
                    tx_state <= IDLE;
                end
            end
        endcase
    end
end

assign UART_Ready = tx_state == IDLE && !tx_start_reg;
assign UART_Busy = tx_state != IDLE;

// Receiver state machine
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_state <= IDLE;
        bit_cnt <= 4'd0;
        start_sampled <= 1'b0;
        UART_Error <= 1'b0;
    end else begin
        case (rx_state)
            IDLE: begin
                if (!RX && !start_sampled) begin // Detect falling edge of start bit
                    start_sampled <= 1'b1;
                    bit_cnt <= 4'd0;
                    rx_state <= DATA_RX;
                end else if (RX)
                    start_sampled <= 1'b0; // Reset the sampled flag when line is high
            end
            DATA_RX: begin
                if (baud_cnt == BIT_PERIOD/2) begin // Sample in the middle of bit period for better timing accuracy
                    shift_reg[bit_cnt] <= RX;
                    if (bit_cnt < 7)
                        bit_cnt <= bit_cnt + 4'd1;
                    else
                        rx_state <= WAIT_STOP;
                end
            end
            WAIT_STOP: begin
                if (baud_cnt == BIT_PERIOD - 1) begin
                    if (RX != 1'b1) // Check for stop bit error
                        UART_Error <= 1'b1;
                    data_out <= shift_reg;
                    rx_state <= IDLE; // Ready to receive next byte
                end
            end
        endcase
    end
end

endmodule