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
    // Parameters for SPI Mode 0: CPOL=0, CPHA=0
    parameter int CPOL = 0;
    parameter int CPHA = 0;

    // State Machine States
    typedef enum logic [1:0] {
        IDLE,
        START,
        TRANSFER,
        DONE
    } state_t;

    state_t current_state, next_state;

    // Data registers
    logic [7:0] shift_reg;
    logic [2:0] bit_counter; // Counter for 8 bits

    // Clock generation for SPI (CPOL=0)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= CPOL;
        end
        else if (current_state == TRANSFER) begin
            SPI_CLK <= ~SPI_CLK;
        end
        else begin
            SPI_CLK <= CPOL;
        end
    end

    // State Machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

    // Next State Logic
    always_comb begin
        next_state = current_state; // Default state remains the same
        case (current_state)
            IDLE: begin
                SPI_EN = 1'b0;
                if (SPI_start) begin
                    next_state = START;
                end
            end
            START: begin
                SPI_EN = 1'b1;
                next_state = TRANSFER;
            end
            TRANSFER: begin
                SPI_EN = 1'b1;
                if (bit_counter == 3'd7 && SPI_CLK == !CPOL) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                SPI_EN = 1'b0;
                next_state = IDLE;
            end
        endcase
    end

    // Data handling and bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'b0;
            bit_counter <= 3'd0;
            SPI_MOSI <= 1'b0;
            data_out <= 8'b0;
        end
        else begin
            case (current_state)
                IDLE: begin
                    if (SPI_start) begin
                        shift_reg <= data_in;
                        bit_counter <= 3'd0;
                    end
                end
                TRANSFER: begin
                    if (SPI_CLK == !CPOL) begin
                        SPI_MOSI <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], SPI_MISO};
                        bit_counter <= bit_counter + 3'd1;
                    end
                end
                DONE: begin
                    data_out <= shift_reg;
                end
            endcase
        end
    end

endmodule