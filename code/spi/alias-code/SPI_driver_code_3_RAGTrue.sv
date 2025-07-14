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
    parameter CPOL = 0; // Clock Polarity
    parameter CPHA = 0; // Clock Phase

    // Internal signals
    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic shift_out;
    logic shift_in;
    logic clk_div;
    logic [3:0] clk_div_cnt;

    // SPI control signals
    assign SPI_EN = SPI_start;

    // Clock divider
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_cnt <= 4'b0000;
            clk_div <= 1'b0;
        end else begin
            if (clk_div_cnt == 4'd15) begin
                clk_div_cnt <= 4'b0000;
                clk_div <= ~clk_div;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1;
            end
        end
    end

    // SPI clock generation
    assign SPI_CLK = clk_div;

    // SPI data shift
    always_ff @(posedge SPI_CLK or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'b00000000;
            bit_cnt <= 3'b000;
            shift_out <= 1'b0;
            shift_in <= 1'b0;
        end else if (SPI_start) begin
            if (bit_cnt == 3'b111) begin
                bit_cnt <= 3'b000;
                shift_out <= 1'b0;
                shift_in <= 1'b0;
            end else begin
                if (CPHA == 0) begin
                    shift_reg <= {shift_reg[6:0], data_in[bit_cnt]};
                    shift_out <= data_in[bit_cnt];
                    bit_cnt <= bit_cnt + 1;
                end else begin
                    shift_out <= data_in[bit_cnt];
                    bit_cnt <= bit_cnt + 1;
                    shift_reg <= {shift_reg[6:0], SPI_MISO};
                end
            end
        end
    end

    // SPI data output
    assign SPI_MOSI = shift_out;

    // SPI data input
    assign data_out = shift_reg;

endmodule