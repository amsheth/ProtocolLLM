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
    localparam CPHA = 1; // Clock Phase

    // Internal signals
    logic [2:0] bit_counter; // Counter for bits in a byte
    logic [7:0] shift_reg;   // Shift register for data
    logic clk_div;           // Divided clock for SPI
    logic clk_div_reg;       // Registered clock for SPI
    logic mosi_reg;          // Registered MOSI output
    logic miso_reg;          // Registered MISO input
    logic start_reg;         // Registered start signal
    logic [7:0] data_out_reg; // Registered data output

    // Clock divider for SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_reg <= 0;
        end else begin
            clk_div_reg <= ~clk_div_reg; // Simple divide by 2
        end
    end

    // Assign SPI clock based on CPOL
    assign SPI_CLK = CPOL ? ~clk_div_reg : clk_div_reg;

    // Shift register and data handling
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 0;
            shift_reg <= 0;
            data_out_reg <= 0;
            SPI_EN <= 0;
            mosi_reg <= 0;
            start_reg <= 0;
        end else begin
            if (SPI_start && !start_reg) begin // Start of new transfer
                bit_counter <= 7; // Start with MSB
                shift_reg <= data_in;
                SPI_EN <= 1;
                start_reg <= 1;
            end else if (SPI_EN) begin
                if (clk_div_reg != clk_div) begin // On rising edge of SPI_CLK
                    if (CPHA == 1) begin // CPHA = 1, data sampled on rising edge
                        miso_reg <= SPI_MISO;
                    end
                    if (bit_counter > 0) begin
                        bit_counter <= bit_counter - 1;
                        shift_reg <= {shift_reg[6:0], 1'b0}; // Shift out MSB
                        mosi_reg <= shift_reg[7];
                    end else begin
                        SPI_EN <= 0; // End of transfer
                        data_out_reg <= {miso_reg, data_out_reg[7:1]}; // Shift in LSB
                    end
                end else begin // On falling edge of SPI_CLK
                    if (CPHA == 0) begin // CPHA = 0, data sampled on falling edge
                        miso_reg <= SPI_MISO;
                    end
                    if (bit_counter == 0) begin
                        data_out_reg <= {miso_reg, data_out_reg[7:1]}; // Shift in LSB
                    end
                end
            end else begin
                start_reg <= 0;
            end
        end
    end

    // Assign outputs
    assign SPI_MOSI = mosi_reg;
    assign data_out = data_out_reg;

endmodule