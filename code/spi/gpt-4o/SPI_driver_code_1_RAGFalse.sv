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

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        SHIFT = 2'b01,
        DONE = 2'b10
    } state_t;

    state_t current_state, next_state;
    logic [7:0] shift_reg;
    logic [2:0] bit_counter;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            SPI_CLK <= CPOL; // CPOL=1
            SPI_EN <= 1'b0; // SPI_EN low, chip not selected
        end else begin
            current_state <= next_state;
        end
    end

    always_ff @(posedge clk) begin
        // Generate SPI clock with CPHA=0 manner
        if (!rst && current_state == SHIFT) begin
            SPI_CLK <= ~SPI_CLK;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            SPI_MOSI <= 1'b0;
            shift_reg <= 8'b0;
            bit_counter <= 3'b0;
            data_out <= 8'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    if (SPI_start) begin
                        shift_reg <= data_in;
                        SPI_EN <= 1'b1; // Activate chip select
                        bit_counter <= 3'd7;
                        SPI_MOSI <= data_in[7];
                    end
                end
                
                SHIFT: begin
                    if (SPI_CLK == ~CPOL) begin
                        SPI_MOSI <= shift_reg[bit_counter];
                        shift_reg <= {shift_reg[6:0], SPI_MISO};  // Shift in MISO bit
                        if (bit_counter == 3'd0) begin
                            data_out <= {shift_reg[6:0], SPI_MISO};
                        end
                    end
                    bit_counter <= bit_counter - 1;
                end

                DONE: begin
                    SPI_EN <= 1'b0; // Deactivate chip select
                    SPI_CLK <= CPOL;
                end

                default: begin
                    SPI_EN <= 1'b0; // Deactivate chip select
                    SPI_CLK <= CPOL;
                end
            endcase
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: if (SPI_start) next_state = SHIFT;
            SHIFT: if (bit_counter == 3'd0 && SPI_CLK == ~CPOL) next_state = DONE;
            DONE: next_state = IDLE;
        endcase
    end

endmodule