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

    localparam CPOL = 0; // Clock Polarity
    localparam CPHA = 1; // Clock Phase

    logic [2:0] bit_cnt;
    logic [7:0] shift_reg;
    logic clk_div;
    logic clk_div_reg;
    logic clk_div_reg2;
    logic mosi_reg;
    logic miso_reg;
    logic start_reg;
    logic [7:0] data_out_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_reg <= 0;
            clk_div_reg2 <= 0;
            bit_cnt <= 0;
            shift_reg <= 0;
            SPI_CLK <= CPOL;
            SPI_MOSI <= 0;
            SPI_EN <= 0;
            data_out_reg <= 0;
            start_reg <= 0;
        end else begin
            clk_div_reg <= ~clk_div_reg;
            clk_div_reg2 <= clk_div_reg;
            clk_div <= clk_div_reg ^ clk_div_reg2;

            if (SPI_start && !start_reg) begin
                bit_cnt <= 7;
                shift_reg <= data_in;
                SPI_EN <= 1;
            end else if (SPI_EN) begin
                if (clk_div) begin
                    if (CPHA == 0) begin
                        SPI_MOSI <= shift_reg[7];
                    end else begin
                        miso_reg <= SPI_MISO;
                    end
                end else begin
                    if (CPHA == 1) begin
                        SPI_MOSI <= shift_reg[7];
                    end else begin
                        miso_reg <= SPI_MISO;
                    end

                    if (bit_cnt > 0) begin
                        shift_reg <= {shift_reg[6:0], miso_reg};
                        bit_cnt <= bit_cnt - 1;
                    end else begin
                        SPI_EN <= 0;
                        data_out_reg <= {shift_reg[6:0], miso_reg};
                    end
                end
            end

            start_reg <= SPI_start;
        end
    end

    assign SPI_CLK = CPOL ^ clk_div;
    assign SPI_MOSI = mosi_reg;
    assign data_out = data_out_reg;

endmodule