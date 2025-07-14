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

    parameter CPOL = 0;
    parameter CPHA = 1;

    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic SPI_MOSI_reg;
    logic SPI_CLK_reg;
    logic SPI_EN_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'b0;
            bit_cnt <= 3'b0;
            SPI_MOSI_reg <= 1'b0;
            SPI_CLK_reg <= 1'b0;
            SPI_EN_reg <= 1'b0;
            data_out <= 8'b0;
        end else begin
            if (SPI_start) begin
                shift_reg <= data_in;
                bit_cnt <= 3'b0;
                SPI_EN_reg <= 1'b1;
            end else if (SPI_EN_reg) begin
                if (CPHA == 0) begin
                    if (bit_cnt == 3'b0) begin
                        SPI_MOSI_reg <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                    end else begin
                        SPI_MOSI_reg <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], SPI_MISO};
                    end
                end else begin
                    if (bit_cnt == 3'b0) begin
                        SPI_MOSI_reg <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], SPI_MISO};
                    end else begin
                        SPI_MOSI_reg <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                    end
                end
                bit_cnt <= bit_cnt + 1;
                if (bit_cnt == 3'b100) begin
                    SPI_EN_reg <= 1'b0;
                    data_out <= shift_reg;
                end
            end
        end
    end

    assign SPI_MOSI = SPI_MOSI_reg;
    assign SPI_CLK = SPI_CLK_reg;
    assign SPI_EN = SPI_EN_reg;

endmodule