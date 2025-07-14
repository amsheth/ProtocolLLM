module SPI_driver( input logic clk, input logic rst, input logic [7:0] data_in, input logic SPI_MISO, Input logic SPI_start, output logic SPI_MOSI, output logic SPI_CLK, output logic SPI_EN, output logic [7:0] data_out );
  parameter CPOL = 0; // Clock polarity: 0 for active low, 1 for active high
  parameter CPHA = 1; // Clock phase: 0 for sampling on leading edge, 1 for sampling on trailing edge

  logic [7:0] data_out_reg; // Output register
  logic SPI_MOSI_out; // SPI output line
  logic SPI_CLK_out; // SPI clock line
  logic SPI_EN_out; // SPI enable line

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      data_out_reg <= 8'h0; // Initialize output register to 0
      SPI_MOSI_out <= 1'b0; // Initialize SPI output line to low
      SPI_CLK_out <= 1'b0; // Initialize SPI clock line to low
      SPI_EN_out <= 1'b0; // Initialize SPI enable line to low
    end else begin
      if (SPI_start) begin // If start signal is asserted, start transmitting data
        SPI_MOSI_out <= data_in[7]; // Send MSB first
        data_out_reg <= {data_out_reg, data_in}; // Shift in new data
        SPI_CLK_out <= 1'b1; // Generate clock pulse
        if (CPOL) begin // If CPOL = 1, invert clock polarity
          SPI_EN_out <= ~SPI_EN_out;
        end else begin
          SPI_EN_out <= 1'b0;
        end
      end else begin // If start signal is not asserted, remain in idle state
        data_out_reg <= 8'h0; // Clear output register
        SPI_MOSI_out <= 1'b0; // Clear SPI output line
        SPI_CLK_out <= 1'b0; // Clear SPI clock line
        SPI_EN_out <= 1'b0; // Clear SPI enable line
      end
    end
  end

  assign data_out = data_out_reg; // Assign output register to output port
  assign SPI_MOSI = SPI_MOSI_out; // Assign SPI output line to output port
  assign SPI_CLK = SPI_CLK_out; // Assign SPI clock line to output port
  assign SPI_EN = SPI_EN_out; // Assign SPI enable line to output port

endmodule