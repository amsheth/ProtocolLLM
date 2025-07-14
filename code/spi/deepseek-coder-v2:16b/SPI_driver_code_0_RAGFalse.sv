module SPI_driver(
    input logic clk,
    input logic rst,
    input logic [7:0] data_in,
    input logic SPI_MISO,
    Input logic SPI_start,
    output logic SPI_MOSI,
    output logic SPI_CLK,
    output logic SPI_EN,
    output logic [7:0] data_out
);

// CPOL = 1 and CPHA = 1 parameters
localparam CPOL = 1;
localparam CPHA = 1;

// Internal signals for state machine
logic [2:0] state;
logic [3:0] bit_count;
logic [7:0] shift_reg;
logic SPI_start_dly;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= 3'b000;
        bit_count <= 4'b0000;
        shift_reg <= 8'b00000000;
        SPI_MOSI <= 1'b0;
        SPI_CLK <= CPOL ^ CPHA; // CPOL = 1, CPHA = 1
        SPI_EN <= 1'b0;
        data_out <= 8'b00000000;
    end else begin
        case (state)
            3'b000: begin // Idle state
                if (SPI_start && !SPI_start_dly) begin
                    SPI_EN <= 1'b1;
                    shift_reg <= data_in;
                    bit_count <= 4'b1000;
                    state <= 3'b001;
                end else begin
                    SPI_EN <= 1'b0;
                end
            end
            3'b001: begin // Start condition setup
                SPI_CLK <= CPOL ^ CPHA;
                if (CPHA == 1) begin
                    SPI_MOSI <= shift_reg[7];
                end
                state <= 3'b010;
            end
            3'b010: begin // Clock high, data sampling or shifting
                SPI_CLK <= CPOL ^ CPHA;
                if (CPHA == 0) begin
                    SPI_MOSI <= shift_reg[7];
                end else begin
                    shift_reg <= {shift_reg[6:0], SPI_MISO};
                end
                state <= 3'b011;
            end
            3'b011: begin // Clock low, data shifting or sampling
                if (CPHA == 1) begin
                    shift_reg <= {shift_reg[6:0], SPI_MISO};
                end
                state <= 3'b100;
            end
            3'b100: begin // End of bit frame
                SPI_CLK <= CPOL ^ CPHA;
                if (CPHA == 1) begin
                    shift_reg <= {shift_reg[6:0], SPI_MISO};
                end
                if (bit_count == 4'b1000) begin
                    data_out <= shift_reg;
                    state <= 3'b101;
                end else begin
                    bit_count <= bit_count - 1;
                    state <= 3'b001;
                end
            end
            3'b101: begin // Data output and deassertion of SPI_EN
                if (bit_count == 4'b1000) begin
                    SPI_EN <= 1'b0;
                end
                state <= 3'b000;
            end
        endcase
    end
end

// Delay the start signal for one clock cycle
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        SPI_start_dly <= 1'b0;
    end else begin
        SPI_start_dly <= SPI_start;
    end
end

endmodule