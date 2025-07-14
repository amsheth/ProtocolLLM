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

    // Parameters for SPI configuration
    localparam CPOL = 0; // Clock Polarity
    localparam CPHA = 0; // Clock Phase

    // Internal signals
    logic [2:0] bit_counter;
    logic [7:0] shift_reg;
    logic clk_div;
    logic clk_div_reg;
    logic clk_div_reg2;
    logic mosi_reg;
    logic miso_reg;
    logic start_reg;
    logic [7:0] data_out_reg;

    // Clock divider to generate SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_reg <= 0;
            clk_div_reg2 <= 0;
        end else begin
            clk_div_reg <= ~clk_div_reg;
            clk_div_reg2 <= clk_div_reg;
        end
    end

    assign clk_div = clk_div_reg2;

    // SPI clock generation based on CPOL
    assign SPI_CLK = CPOL ? ~clk_div : clk_div;

    // SPI enable signal
    assign SPI_EN = start_reg;

    // SPI start signal synchronization and edge detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            start_reg <= 0;
        end else begin
            start_reg <= SPI_start;
        end
    end

    // SPI data transmission and reception
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 0;
            shift_reg <= 0;
            mosi_reg <= 0;
            miso_reg <= 0;
            data_out_reg <= 0;
        end else if (start_reg) begin
            if (bit_counter == 0) begin
                shift_reg <= data_in;
                bit_counter <= 8;
            end else begin
                if (clk_div_reg2) begin
                    // Shift out data on rising edge of SPI_CLK
                    mosi_reg <= shift_reg[7];
                    shift_reg <= {shift_reg[6:0], 1'b0};
                end else begin
                    // Shift in data on falling edge of SPI_CLK
                    miso_reg <= SPI_MISO;
                    data_out_reg <= {data_out_reg[6:0], miso_reg};
                    bit_counter <= bit_counter - 1;
                end
            end
        end
    end

    // Assign output signals
    assign SPI_MOSI = mosi_reg;
    assign data_out = data_out_reg;

endmodule