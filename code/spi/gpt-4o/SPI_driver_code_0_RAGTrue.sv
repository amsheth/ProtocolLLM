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

    // Parameters for CPOL and CPHA
    parameter CPOL = 1;
    parameter CPHA = 1;

    // Internal signals
    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic spi_active;

    // SPI Clock generation based on CPOL and CPHA
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= CPOL;
        end else if (spi_active) begin
            SPI_CLK <= ~SPI_CLK;
        end else begin
            SPI_CLK <= CPOL;
        end
    end

    // SPI Enable and shift register logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_EN <= 1'b0;
            shift_reg <= 8'b0;
            bit_count <= 3'b0;
            spi_active <= 1'b0;
        end else if (SPI_start) begin
            SPI_EN <= 1'b1;
            shift_reg <= data_in;
            bit_count <= 3'b111;
            spi_active <= 1'b1;
        end else if (spi_active) begin
            if (~CPHA ? SPI_CLK == ~CPOL : SPI_CLK == CPOL) begin
                SPI_MOSI <= shift_reg[7];
                shift_reg <= {shift_reg[6:0], SPI_MISO};
                if (bit_count == 3'b0) begin
                    spi_active <= 1'b0;
                    SPI_EN <= 1'b0;
                    data_out <= shift_reg;
                end else begin
                    bit_count <= bit_count - 1;
                end
            end
        end
    end

endmodule