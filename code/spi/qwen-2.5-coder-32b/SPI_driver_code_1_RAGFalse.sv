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
    localparam CPOL = 1; // Clock Polarity
    localparam CPHA = 0; // Clock Phase

    // Internal signals
    logic [2:0] bit_cnt; // Bit counter for 8-bit data
    logic [7:0] shift_reg; // Shift register for data
    logic clk_div; // Divided clock for SPI
    logic clk_div_reg; // Registered clock for SPI
    logic spi_clk_int; // Internal SPI clock
    logic spi_clk_reg; // Registered SPI clock
    logic spi_en_int; // Internal SPI enable
    logic spi_en_reg; // Registered SPI enable
    logic mosi_int; // Internal MOSI signal
    logic mosi_reg; // Registered MOSI signal
    logic miso_reg; // Registered MISO signal
    logic start_reg; // Registered start signal

    // Clock divider to generate SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 0;
        end else begin
            clk_div <= ~clk_div;
        end
    end

    // Register the divided clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_reg <= 0;
        end else begin
            clk_div_reg <= clk_div;
        end
    end

    // Generate SPI clock based on CPOL
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_int <= CPOL;
        end else if (clk_div_reg) begin
            spi_clk_int <= ~spi_clk_int;
        end
    end

    // Register the SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_reg <= CPOL;
        end else begin
            spi_clk_reg <= spi_clk_int;
        end
    end

    // Generate SPI enable signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_en_int <= 0;
        end else if (SPI_start) begin
            spi_en_int <= 1;
        end else if (bit_cnt == 3'b111) begin
            spi_en_int <= 0;
        end
    end

    // Register the SPI enable signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_en_reg <= 0;
        end else begin
            spi_en_reg <= spi_en_int;
        end
    end

    // Register the start signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            start_reg <= 0;
        end else begin
            start_reg <= SPI_start;
        end
    end

    // SPI clock and enable outputs
    assign SPI_CLK = spi_clk_reg;
    assign SPI_EN = spi_en_reg;

    // MOSI signal generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mosi_int <= 0;
        end else if (spi_en_int && (spi_clk_int == CPOL)) begin
            mosi_int <= shift_reg[7];
        end
    end

    // Register the MOSI signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mosi_reg <= 0;
        end else begin
            mosi_reg <= mosi_int;
        end
    end

    // Assign MOSI output
    assign SPI_MOSI = mosi_reg;

    // Shift register and bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'b0;
            bit_cnt <= 3'b0;
        end else if (spi_en_int && (spi_clk_int == CPOL)) begin
            if (CPHA == 0) begin
                shift_reg <= {shift_reg[6:0], SPI_MISO};
                bit_cnt <= bit_cnt + 1;
            end
        end else if (spi_en_int && (spi_clk_int != CPOL)) begin
            if (CPHA == 1) begin
                shift_reg <= {shift_reg[6:0], SPI_MISO};
                bit_cnt <= bit_cnt + 1;
            end
        end
    end

    // Register the MISO signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            miso_reg <= 0;
        end else begin
            miso_reg <= SPI_MISO;
        end
    end

    // Output data register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'b0;
        end else if (bit_cnt == 3'b111 && spi_clk_int == CPOL) begin
            data_out <= shift_reg;
        end
    end

endmodule