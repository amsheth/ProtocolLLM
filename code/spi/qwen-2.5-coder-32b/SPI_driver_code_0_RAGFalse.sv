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

    localparam CPOL = 1;
    localparam CPHA = 1;

    logic [2:0] bit_cnt;
    logic [7:0] shift_reg;
    logic clk_div;
    logic clk_div_reg;
    logic spi_clk_int;
    logic spi_clk_reg;
    logic spi_en_int;
    logic [7:0] data_out_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_reg <= 0;
            spi_clk_reg <= CPOL;
            spi_en_int <= 0;
            bit_cnt <= 0;
            shift_reg <= 0;
            data_out_reg <= 0;
        end else begin
            clk_div_reg <= ~clk_div_reg;
            if (clk_div_reg) begin
                spi_clk_reg <= ~spi_clk_reg;
                if (spi_clk_reg == CPOL && spi_en_int) begin
                    if (CPHA == 0) begin
                        if (bit_cnt < 8) begin
                            shift_reg <= {shift_reg[6:0], SPI_MISO};
                            SPI_MOSI <= data_in[7-bit_cnt];
                            bit_cnt <= bit_cnt + 1;
                        end else begin
                            data_out_reg <= shift_reg;
                            spi_en_int <= 0;
                        end
                    end
                end else if (spi_clk_reg != CPOL && spi_en_int) begin
                    if (CPHA == 1) begin
                        if (bit_cnt < 8) begin
                            shift_reg <= {shift_reg[6:0], SPI_MISO};
                            SPI_MOSI <= data_in[7-bit_cnt];
                            bit_cnt <= bit_cnt + 1;
                        end else begin
                            data_out_reg <= shift_reg;
                            spi_en_int <= 0;
                        end
                    end
                end
            end
            if (SPI_start) begin
                spi_en_int <= 1;
                bit_cnt <= 0;
                shift_reg <= 0;
            end
        end
    end

    assign clk_div = clk_div_reg;
    assign SPI_CLK = spi_clk_reg;
    assign SPI_EN = spi_en_int;
    assign data_out = data_out_reg;

endmodule