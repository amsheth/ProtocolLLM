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
logic clk_divider;
logic clk_enable;

// Parameter for clock divider (assuming a 16x division for 8-bit transfer)
parameter CLK_DIV = 4'd15; // For a 16x division

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        SPI_CLK <= 0;
        SPI_MOSI <= 0;
        SPI_EN <= 0;
        bit_count <= 4'd0;
        shift_reg <= 8'b0;
        data_out <= 8'b0;
    end else begin
        // Handle the start of a new transfer
        if (SPI_start) begin
            SPI_CLK <= 0; // CPOL=0, so idle state is low
            SPI_MOSI <= data_in[7]; // Load MSB first
            shift_reg <= data_in;
            bit_count <= 4'd7;
            clk_divider <= CLK_DIV;
            clk_enable <= 1'b1;
        end else if (clk_enable) begin
            // Clock divider logic
            if (clk_divider == 0) begin
                clk_divider <= CLK_DIV;
                SPI_CLK <= ~SPI_CLK; // Toggle clock
            end else begin
                clk_divider <= clk_divider - 1'b1;
            end

            // Data shifting and output
            if (SPI_CLK == 1'b1) begin // CPHA=0, data sampled on rising edge of clock
                SPI_MOSI <= shift_reg[6];
                shift_reg <= {shift_reg[5:0], SPI_MISO};
                bit_count <= bit_count - 1'b1;
            end

            // Transfer completion check
            if (bit_count == 4'd-1) begin
                clk_enable <= 1'b0;
                SPI_EN <= 0;
                data_out <= shift_reg; // Output the received data
            end else begin
                SPI_EN <= 1'b1;
            end
        end
    end
end

endmodule