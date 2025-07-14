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

    // Parameters
    parameter CPOL = 1; // Clock Polarity
    parameter CPHA = 1; // Clock Phase

    // Internal signals
    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic shift_out;
    logic shift_in;
    logic clk_out;
    logic [1:0] state;

    // State definitions
    parameter IDLE = 2'b00;
    parameter SEND = 2'b01;
    parameter RECEIVE = 2'b10;

    // SPI control signals
    assign SPI_EN = (state != IDLE);

    // SPI clock generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= ~CPOL;
        end else begin
            SPI_CLK <= ~SPI_CLK;
        end
    end

    // SPI state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            bit_cnt <= 3'b000;
            shift_reg <= 8'b00000000;
            data_out <= 8'b00000000;
        end else begin
            case (state)
                IDLE:
                    if (SPI_start) begin
                        state <= SEND;
                        shift_reg <= data_in;
                        bit_cnt <= 3'b111;
                    end
                SEND:
                    if (bit_cnt != 3'b000) begin
                        shift_out <= shift_reg[0];
                        shift_reg <= {shift_reg[7:1], SPI_MISO};
                        bit_cnt <= bit_cnt - 1;
                    end else begin
                        state <= RECEIVE;
                    end
                RECEIVE:
                    if (bit_cnt != 3'b000) begin
                        shift_in <= SPI_MISO;
                        shift_reg <= {shift_reg[7:1], shift_in};
                        bit_cnt <= bit_cnt - 1;
                    end else begin
                        data_out <= shift_reg;
                        state <= IDLE;
                    end
                default:
                    state <= IDLE;
            endcase
        end
    end

    // SPI data output
    assign SPI_MOSI = shift_out;

endmodule