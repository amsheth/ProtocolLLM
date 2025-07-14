module UART_driver(
    input  logic       clk,
    input  logic       rst,
    input  logic       UART_Start,
    input  logic [7:0] data_in,
    input  logic       RX,
    output logic       TX,
    output logic [7:0] data_out,
    output logic       UART_Ready,
    output logic       UART_Busy,
    output logic       UART_Error
);

parameter BAUD_RATE = 9600; // Baud rate in bits per second
parameter CLK_FREQ = 50000000; // System clock frequency in Hz

// Calculate the number of clock cycles for one bit time
localparam BIT_TIME = CLK_FREQ / BAUD_RATE;

// State encoding
typedef enum logic [2:0] {
    IDLE,
    START_BIT,
    DATA_BITS,
    PARITY_BIT,
    STOP_BIT,
    RECEIVE_IDLE,
    RECEIVE_START_BIT,
    RECEIVE_DATA_BITS,
    RECEIVE_PARITY_BIT,
    RECEIVE_STOP_BIT
} state_t;

state_t tx_state, rx_state;
logic [3:0] bit_count;
logic [7:0] shift_reg;
logic parity_bit;
logic rx_parity_error;

// Transmit logic
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        tx_state <= IDLE;
        TX <= 1'b1; // Idle state is high
        UART_Ready <= 1'b1;
        UART_Busy <= 1'b0;
    end else begin
        case (tx_state)
            IDLE: begin
                if (UART_Start) begin
                    tx_state <= START_BIT;
                    TX <= 1'b0; // Start bit is low
                    UART_Ready <= 1'b0;
                    UART_Busy <= 1'b1;
                    shift_reg <= data_in;
                    parity_bit <= ^data_in; // Calculate parity bit
                end
            end
            START_BIT: begin
                if (bit_count == BIT_TIME - 1) begin
                    tx_state <= DATA_BITS;
                    bit_count <= 0;
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
            DATA_BITS: begin
                TX <= shift_reg[7];
                shift_reg <= {shift_reg[6:0], 1'b0};
                if (bit_count == BIT_TIME - 1) begin
                    if (parity_bit) begin
                        tx_state <= PARITY_BIT;
                    end else begin
                        tx_state <= STOP_BIT;
                    end
                    bit_count <= 0;
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
            PARITY_BIT: begin
                TX <= parity_bit;
                if (bit_count == BIT_TIME - 1) begin
                    tx_state <= STOP_BIT;
                    bit_count <= 0;
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
            STOP_BIT: begin
                TX <= 1'b1; // Stop bit is high
                if (bit_count == BIT_TIME - 1) begin
                    tx_state <= IDLE;
                    UART_Ready <= 1'b1;
                    UART_Busy <= 1'b0;
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
        endcase
    end
end

// Receive logic
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_state <= RECEIVE_IDLE;
        data_out <= 8'b0;
        UART_Error <= 1'b0;
    end else begin
        case (rx_state)
            RECEIVE_IDLE: begin
                if (!RX) begin
                    rx_state <= RECEIVE_START_BIT;
                    bit_count <= 0;
                end
            end
            RECEIVE_START_BIT: begin
                if (bit_count == BIT_TIME - 1) begin
                    rx_state <= RECEIVE_DATA_BITS;
                    shift_reg <= 8'b0;
                    parity_bit <= 1'b0;
                    rx_parity_error <= 1'b0;
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
            RECEIVE_DATA_BITS: begin
                shift_reg <= {shift_reg[6:0], RX};
                if (bit_count == BIT_TIME - 1) begin
                    parity_bit <= parity_bit ^ RX;
                    if (bit_count == 7 * BIT_TIME - 1) begin
                        rx_state <= RECEIVE_PARITY_BIT;
                    end else begin
                        bit_count <= bit_count + 1;
                    end
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
            RECEIVE_PARITY_BIT: begin
                if (RX != parity_bit) begin
                    rx_parity_error <= 1'b1;
                end
                rx_state <= RECEIVE_STOP_BIT;
                bit_count <= 0;
            end
            RECEIVE_STOP_BIT: begin
                if (bit_count == BIT_TIME - 1) begin
                    data_out <= shift_reg;
                    UART_Error <= rx_parity_error;
                    rx_state <= RECEIVE_IDLE;
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
        endcase
    end
end

endmodule