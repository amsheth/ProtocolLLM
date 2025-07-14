module SPI_driver( input logic clk, input logic rst, input logic [7:0] data_in, input logic SPI_MISO, Input logic SPI_start, output logic SPI_MOSI, output logic SPI_CLK, output logic SPI_EN, output logic [7:0] data_out );

always_ff @(posedge clk or negedge rst) begin
if (!rst) begin
SPI_EN <= 1'b0;
data_out <= 8'd0;
end else begin
SPI_CLK <= SPI_start;
SPI_MOSI <= data_in[7];
if (SPI_EN) begin
data_out <= {data_out[6:0], SPI_MISO};
SPI_EN <= 1'b0;
end else if (SPI_start) begin
SPI_EN <= 1'b1;
end
end
endmodule