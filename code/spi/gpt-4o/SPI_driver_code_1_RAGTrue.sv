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

    // Parameters for the SPI mode 
    parameter CPOL = 1;
    parameter CPHA = 0;

    // Internal registers and variables
    logic [2:0] bit_count;          // Counter for bits being shifted
    logic [7:0] shift_reg;          // Shift register for data input and output
    logic spi_active;               // Indicates if SPI is active

    // Clock generation based on CPOL and CPHA
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= CPOL;
        end else if (spi_active) begin
            if (CPHA == 0) begin
                SPI_CLK <= ~SPI_CLK;
            end else if (bit_count > 0) begin
                SPI_CLK <= ~SPI_CLK;
            end
        end
    end

    // SPI state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_active <= 0;
            SPI_EN <= 0;
            SPI_MOSI <= 0;
            data_out <= 0;
            bit_count <= 0;
            shift_reg <= 0;
        end else if (SPI_start && !spi_active) begin
            // Begin SPI transaction
            spi_active <= 1;
            SPI_EN <= 1;
            bit_count <= 3'b111;  // Start counting from 7 for 8 bits
            shift_reg <= data_in;
        end else if (spi_active) begin
            if (bit_count > 0) begin
                // Transmit data
                if (CPHA == 0) begin
                    SPI_MOSI <= shift_reg[7];
                    shift_reg <= {shift_reg[6:0], SPI_MISO};
                end
                bit_count <= bit_count - 1;
            end else begin
                // Receive data
                if (CPHA == 1) begin
                    SPI_MOSI <= shift_reg[7];
                    shift_reg <= {shift_reg[6:0], SPI_MISO};
                end
                spi_active <= 0;
                SPI_EN <= 0;
                data_out <= shift_reg;
            end
        end
    end

endmodule