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
    logic [2:0] bit_counter; // Counter for bits in a byte
    logic [7:0] shift_reg;   // Shift register for data
    logic clk_div;           // Divided clock for SPI
    logic clk_div_reg;       // Registered clock for SPI
    logic clk_div_sync;      // Synchronized clock for SPI
    logic mosi_reg;          // Registered MOSI output
    logic miso_reg;          // Registered MISO input
    logic start_reg;         // Registered start signal
    logic [7:0] data_out_reg;// Registered data output

    // Clock divider for SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 1'b0;
        end else begin
            clk_div <= ~clk_div;
        end
    end

    // Synchronize divided clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_reg <= 1'b0;
            clk_div_sync <= 1'b0;
        end else begin
            clk_div_reg <= clk_div;
            clk_div_sync <= clk_div_reg;
        end
    end

    // Register start signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            start_reg <= 1'b0;
        end else begin
            start_reg <= SPI_start;
        end
    end

    // SPI clock generation with CPOL and CPHA
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= CPOL;
        end else if (clk_div_sync) begin
            SPI_CLK <= ~SPI_CLK;
        end
    end

    // SPI enable signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_EN <= 1'b0;
        end else if (start_reg) begin
            SPI_EN <= 1'b1;
        end else if (bit_counter == 3'b111) begin
            SPI_EN <= 1'b0;
        end
    end

    // SPI data shift register and output
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 3'b000;
            shift_reg <= 8'b0;
            mosi_reg <= 1'b0;
            data_out_reg <= 8'b0;
        end else if (start_reg) begin
            bit_counter <= 3'b111;
            shift_reg <= data_in;
            mosi_reg <= shift_reg[7];
        end else if (clk_div_sync) begin
            if (bit_counter != 3'b000) begin
                bit_counter <= bit_counter - 1;
                shift_reg <= {shift_reg[6:0], 1'b0};
                mosi_reg <= shift_reg[7];
            end else begin
                data_out_reg <= shift_reg;
            end
        end
    end

    // Register MISO input
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            miso_reg <= 1'b0;
        end else if (clk_div_sync) begin
            miso_reg <= SPI_MISO;
        end
    end

    // Shift in MISO data
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'b0;
        end else if (clk_div_sync && bit_counter != 3'b111) begin
            data_out_reg <= {data_out_reg[6:0], miso_reg};
        end else if (bit_counter == 3'b000) begin
            data_out <= data_out_reg;
        end
    end

    // Assign outputs
    assign SPI_MOSI = mosi_reg;

endmodule