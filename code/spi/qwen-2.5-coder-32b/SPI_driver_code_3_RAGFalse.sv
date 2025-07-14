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
    localparam CPHA = 0; // Clock Phase

    logic [2:0] bit_cnt; // Bit counter for 8-bit data
    logic [7:0] shift_reg; // Shift register for data
    logic clk_div; // Divided clock for SPI
    logic clk_div_reg; // Registered divided clock
    logic spi_clk_int; // Internal SPI clock
    logic spi_clk_reg; // Registered SPI clock
    logic spi_en_int; // Internal SPI enable
    logic [7:0] data_out_reg; // Registered output data

    // Clock divider to generate SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_reg <= 1'b0;
        end else begin
            clk_div_reg <= ~clk_div_reg;
        end
    end

    assign clk_div = clk_div_reg;

    // SPI clock generation based on CPOL
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_reg <= CPOL;
        end else begin
            spi_clk_reg <= clk_div;
        end
    end

    assign spi_clk_int = spi_clk_reg;

    // SPI enable generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_en_int <= 1'b0;
        end else if (SPI_start) begin
            spi_en_int <= 1'b1;
        end else if (bit_cnt == 3'b111) begin
            spi_en_int <= 1'b0;
        end
    end

    assign SPI_EN = spi_en_int;

    // SPI clock and MOSI output
    always_ff @(posedge spi_clk_int or posedge rst) begin
        if (rst) begin
            bit_cnt <= 3'b0;
            shift_reg <= 8'b0;
            SPI_MOSI <= 1'b0;
            data_out_reg <= 8'b0;
        end else if (spi_en_int) begin
            if (CPHA == 0) begin // Leading edge sampling
                if (bit_cnt == 3'b0) begin
                    shift_reg <= data_in;
                end
                SPI_MOSI <= shift_reg[7];
                shift_reg <= {1'b0, shift_reg[7:1]};
                if (bit_cnt == 3'b111) begin
                    data_out_reg <= {SPI_MISO, data_out_reg[7:1]};
                end
                bit_cnt <= bit_cnt + 1;
            end else begin // Trailing edge sampling
                SPI_MOSI <= shift_reg[7];
                shift_reg <= {1'b0, shift_reg[7:1]};
                if (bit_cnt == 3'b111) begin
                    data_out_reg <= {SPI_MISO, data_out_reg[7:1]};
                end
                bit_cnt <= bit_cnt + 1;
            end
        end
    end

    assign SPI_CLK = spi_clk_int;
    assign data_out = data_out_reg;

endmodule