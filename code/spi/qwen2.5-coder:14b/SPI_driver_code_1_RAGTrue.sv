module SPI_driver(
    input logic clk,
    input logic rst,
    input logic [7:0] data_in,
    input logic SPI_MISO,
    input logic SPI_start,
    output logic SPI_MOSI,
    output logic SPI_CLK,
    output logic SPI_EN,
    output logic [7:0] data_out
);

// Internal state variables
typedef enum {IDLE, START, DATA_TRANSFER, STOP} state_t;
state_t current_state, next_state;

logic [3:0] bit_count; // Bit counter for 8-bit transfer
logic [7:0] shift_reg; // Shift register to hold data

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        current_state <= IDLE;
        SPI_CLK <= 1'b1; // CPOL=1, so idle state is high
        SPI_MOSI <= 1'b0;
        SPI_EN <= 1'b0;
        bit_count <= 4'd0;
        shift_reg <= 8'd0;
    end else begin
        current_state <= next_state;
        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state <= START;
                    SPI_EN <= 1'b1;
                    bit_count <= 4'd7; // Start from MSB
                    shift_reg <= data_in;
                end else begin
                    next_state <= IDLE;
                end
            end
            START: begin
                next_state <= DATA_TRANSFER;
                SPI_CLK <= 1'b0; // CPHA=0, so clock goes low first
            end
            DATA_TRANSFER: begin
                if (bit_count == 4'd0) begin
                    next_state <= STOP;
                end else begin
                    next_state <= DATA_TRANSFER;
                    bit_count <= bit_count - 1;
                end
                SPI_CLK <= ~SPI_CLK; // Toggle clock
                shift_reg <= {shift_reg[6:0], SPI_MISO}; // Shift in MISO data
            end
            STOP: begin
                next_state <= IDLE;
                SPI_EN <= 1'b0;
                data_out <= shift_reg; // Output received data
            end
        endcase
    end
end

// Assign MOSI based on the current bit being transmitted
assign SPI_MOSI = (current_state == DATA_TRANSFER) ? shift_reg[7] : 1'b0;

endmodule