module SPI_driver( input logic clk, rst, input logic [7:0] data_in, 
SPI_MISO, SPI_start, output logic SPI_MOSI, SPI_CLK, SPI_EN, output logic [7:0] data_out );

// Declare local parameters
localparam CPOL = 1'b1; // Clock polarity
localparam CPHA = 1'b0; // Clock phase
localparam CLK_HIGH = 32'hFFFFFFFF; // SPI clock high period
localparam CLK_LOW = 32'h00000000; // SPI clock low period
localparam DATA_WIDTH = 8; // SPI data width in bits

// Declare internal signals
logic [DATA_WIDTH-1:0] sck; // Serial clock signal
logic [DATA_WIDTH-1:0] cs; // Chip select signal
logic [DATA_WIDTH-1:0] miso; // Master input slave output
logic [DATA_WIDTH-1:0] mosi; // Master output slave input

// Clock generation
always_ff @(posedge clk or negedge rst) begin
if (~rst) begin
sck <= 1'b0;
end else if (SPI_start) begin
sck <= ~sck; // Toggle sck on SPI start
end
end

// Chip select generation
always_ff @(posedge clk or negedge rst) begin
if (~rst) begin
cs <= 1'b1;
end else if (SPI_start) begin
cs <= ~cs; // Toggle cs on SPI start
end
end

// MISO sampling
always_ff @(posedge clk or negedge rst) begin
if (~rst) begin
miso <= 1'b0;
end else if (SPI_start && sck == CPOL) begin // Sample miso on rising edge of sck
miso <= SPI_MISO;
end
end

// MOSI generation
always_ff @(posedge clk or negedge rst) begin
if (~rst) begin
mosi <= 1'b0;
end else if (SPI_start && sck == CPOL) begin // Generate mosi on rising edge of sck
mosi <= data_in;
end
end

// SPI enable generation
always_ff @(posedge clk or negedge rst) begin
if (~rst) begin
SPI_EN <= 1'b0;
end else if (SPI_start) begin // Set SPI_EN high when SPI transaction starts
SPI_EN <= 1'b1;
end else if (SPI_start && sck == CPOL) begin // Clear SPI_EN when SPI transaction ends
SPI_EN <= 1'b0;
end
end

// Data output generation
always_ff @(posedge clk or negedge rst) begin
if (~rst) begin
data_out <= 1'b0;
end else if (SPI_start && sck == CPOL) begin // Output data when SPI transaction ends
data_out <= miso;
end
end

endmodule