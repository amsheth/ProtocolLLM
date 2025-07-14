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
    // CPOL = 0 and CPHA = 0 means Clock Polarity (CPOL) is low when idle and Clock Phase (CPHA) is sampling on the first edge.

    enum logic {IDLE, START, TRANSFER, STOP} state, next_state;
    logic [2:0] bit_count;
    logic [7:0] shift_reg;
    logic clk_div;

    // Clock Divider to generate SPI clock (assuming 16x faster than input clock)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 0;
        end else begin
            clk_div <= ~clk_div; // Simple divide-by-two for demonstration purposes
        end
    end

    // SPI Clock Generation
    assign SPI_CLK = (~CPOL & clk_div) | (CPOL & ~clk_div);

    // State Machine Logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            bit_count <= 0;
            shift_reg <= 0;
        end else begin
            state <= next_state;
            case (next_state)
                TRANSFER: begin
                    if (bit_count < 7) begin
                        bit_count <= bit_count + 1;
                    end else begin
                        bit_count <= 0;
                    end
                    shift_reg <= {shift_reg[6:0], SPI_MISO}; // Shift in data on MOSI if CPHA=0
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = START;
                    bit_count = 0;
                    shift_reg = data_in;
                end
            end
            START: begin
                next_state = TRANSFER;
            end
            TRANSFER: begin
                if (bit_count == 7) begin
                    next_state = STOP;
                end
            end
            STOP: begin
                // End of transfer, no action needed except to reset start signal if necessary.
            end
        endcase
    end

    // Output Logic for SPI signals
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_MOSI <= 0;
            SPI_EN <= 0;
        end else begin
            case (state)
                TRANSFER: begin
                    SPI_MOSI <= shift_reg[7]; // Output the MSB first
                end
                STOP: begin
                    SPI_EN <= 0; // Deassert EN after transfer if necessary, or adjust based on requirements.
                end
            endcase
        end
    end

    assign data_out = shift_reg;
endmodule