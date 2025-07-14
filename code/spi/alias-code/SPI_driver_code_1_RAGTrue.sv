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

    parameter CPOL = 1;
    parameter CPHA = 0;

    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic [1:0] state;
    logic SPI_MOSI_reg;

    typedef enum logic [1:0] {
        IDLE,
        START,
        TRANSFER,
        END
    } state_t;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            SPI_EN <= 0;
            SPI_CLK <= CPOL;
            SPI_MOSI <= 0;
            shift_reg <= 8'b0;
            bit_cnt <= 3'b0;
            data_out <= 8'b0;
        end else begin
            case (state)
                IDLE: begin
                    SPI_EN <= 0;
                    if (SPI_start) begin
                        state <= START;
                        shift_reg <= data_in;
                        bit_cnt <= 3'b0;
                    end
                end
                START: begin
                    SPI_EN <= 1;
                    SPI_CLK <= ~CPOL;
                    SPI_MOSI <= shift_reg[7];
                    shift_reg <= {shift_reg[6:0], 1'b0};
                    bit_cnt <= bit_cnt + 1;
                    state <= TRANSFER;
                end
                TRANSFER: begin
                    SPI_CLK <= ~SPI_CLK;
                    if (bit_cnt < 8) begin
                        SPI_MOSI <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bit_cnt <= bit_cnt + 1;
                    end else begin
                        state <= END;
                    end
                end
                END: begin
                    SPI_CLK <= CPOL;
                    data_out <= shift_reg;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule