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
    logic [2:0] bit_counter;  // Counter for bits (8 bits per byte)
    logic [7:0] shift_reg;    // Shift register to hold the outgoing and incoming data
    logic clk_divider;        // Clock divider signal
    logic spi_clk_int;        // Internal SPI clock
    logic spi_clk_prev;       // Previous state of internal SPI clock
    logic mosi_out;           // Output for MOSI line
    logic miso_in;            // Input from MISO line

    // Parameters for CPOL=1 and CPHA=1
    localparam CLK_IDLE = 1'b1;
    localparam CLK_ACTIVE = 1'b0;

    // Clock divider to generate SPI clock (assuming clk is the system clock)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 1'b0;
        end else begin
            clk_divider <= ~clk_divider;  // Toggle every cycle of system clock
        end
    end

    // Generate SPI_CLK based on CPOL=1 and CPHA=1
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_int <= CLK_IDLE;
        end else begin
            spi_clk_int <= clk_divider;  // Active low clock with CPOL=1
        end
    end

    // SPI_EN signal to enable the SPI communication
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_EN <= 1'b0;
        end else if (SPI_start) begin
            SPI_EN <= 1'b1;
        end else if (bit_counter == 3'd7 && spi_clk_prev != spi_clk_int) begin
            SPI_EN <= 1'b0;  // Disable after last bit is sent/received
        end
    end

    // Shift register for data transmission and reception
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'd0;
            bit_counter <= 3'd0;
            mosi_out <= 1'b0;
            miso_in <= 1'b0;
            data_out <= 8'd0;
        end else if (SPI_start && spi_clk_prev != spi_clk_int) begin
            shift_reg <= data_in;  // Load new data to send
            bit_counter <= 3'd0;
        end else if (spi_clk_prev != spi_clk_int) begin
            if (bit_counter < 3'd8) begin
                mosi_out <= shift_reg[7];  // Send MSB first
                miso_in <= SPI_MISO;       // Capture MISO data on rising edge of clock

                // Shift the register left and increment bit counter
                shift_reg <= {shift_reg[6:0], 1'b0};
                bit_counter <= bit_counter + 3'd1;
            end else begin
                data_out <= miso_in;  // Store received data after all bits are received
            end
        end

        spi_clk_prev <= spi_clk_int;  // Save current clock state for edge detection
    end

    // Assign outputs
    assign SPI_CLK = spi_clk_int;
    assign SPI_MOSI = mosi_out;

endmodule