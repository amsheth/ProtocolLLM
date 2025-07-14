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
    localparam CPHA = 1; // Clock Phase

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
    assign SPI_EN = 1'b1;

    // Start signal synchronization
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            start_reg <= 0;
        end else begin
            start_reg <= SPI_start;
        end
    end

    // Main SPI state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 3'b000;
            shift_reg <= 8'b0;
            data_out_reg <= 8'b0;
            SPI_MOSI <= 0;
        end else if (start_reg) begin
            if (bit_counter < 8) begin
                if (CPHA == 0) begin // CPHA = 0
                    if (clk_div_reg2 == 0) begin
                        SPI_MOSI <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                    end
                    if (clk_div_reg2 == 1) begin
                        miso_reg <= SPI_MISO;
                    end
                end else begin // CPHA = 1
                    if (clk_div_reg2 == 1) begin
                        SPI_MOSI <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                    end
                    if (clk_div_reg2 == 0) begin
                        miso_reg <= SPI_MISO;
                    end
                end
                bit_counter <= bit_counter + 1;
            end else begin
                data_out_reg <= {miso_reg, data_out_reg[7:1]};
                bit_counter <= 3'b000;
                start_reg <= 0;
            end
        end
    end

    // Output assignments
    assign SPI_MOSI = mosi_reg;
    assign data_out = data_out_reg;

endmodule