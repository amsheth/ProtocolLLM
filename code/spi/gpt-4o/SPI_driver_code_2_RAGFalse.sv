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
    // Define parameters for SPI configuration
    parameter CPOL = 0;
    parameter CPHA = 1;
    localparam IDLE = 0, TRANSFER = 1;
    
    // Internal registers and variables
    logic [7:0] shift_reg;
    logic [2:0] bit_counter;
    logic state;

    // Generate SPI clock with CPOL=0 and CPHA=1 configuration
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= CPOL;
        end else if (state == TRANSFER) begin
            SPI_CLK <= ~SPI_CLK;
        end else begin
            SPI_CLK <= CPOL;
        end
    end

    // State machine for SPI master driver
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            SPI_EN <= 1'b0;
            bit_counter <= 3'd0;
            shift_reg <= 8'b0;
            data_out <= 8'b0;
        end else begin
            case (state)
                IDLE: begin
                    SPI_EN <= 1'b0;
                    if (SPI_start) begin
                        state <= TRANSFER;
                        SPI_EN <= 1'b1;
                        shift_reg <= data_in;
                        bit_counter <= 3'd7;
                    end
                end
                
                TRANSFER: begin
                    if (SPI_CLK == CPHA) begin
                        SPI_MOSI <= shift_reg[bit_counter];
                        shift_reg <= {shift_reg[6:0], SPI_MISO};
                        if (bit_counter == 0) begin
                            state <= IDLE;
                            SPI_EN <= 1'b0;
                            data_out <= shift_reg;
                        end else begin
                            bit_counter <= bit_counter - 1;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
endmodule