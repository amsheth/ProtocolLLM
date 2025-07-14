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

// Internal signals
logic [3:0] bit_count;
logic [7:0] shift_reg;
logic clk_div;
logic clk_en;

// Parameter for clock divider (assuming 16x division for 8-bit transfer)
parameter CLK_DIV = 15; // For a 16x division

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        SPI_CLK <= 0;
        SPI_MOSI <= 0;
        SPI_EN <= 0;
        bit_count <= 4'b0;
        shift_reg <= 8'b0;
        data_out <= 8'b0;
    end else begin
        // Clock generation logic (16x division)
        if (clk_div == CLK_DIV) begin
            clk_div <= 0;
            SPI_CLK <= ~SPI_CLK; // Toggle clock
        end else begin
            clk_div <= clk_div + 1;
        end

        // State machine for SPI transfer
        if (SPI_start) begin
            bit_count <= 4'b0;
            shift_reg <= data_in;
            SPI_EN <= 1;
        end else if (bit_count < 8 && SPI_CLK == 1) begin // On rising edge of SPI_CLK
            SPI_MOSI <= shift_reg[7];
            shift_reg <= {shift_reg[6:0], SPI_MISO};
            bit_count <= bit_count + 1;
        end else if (bit_count == 8) begin
            data_out <= shift_reg;
            SPI_EN <= 0;
        end
    end
end

endmodule