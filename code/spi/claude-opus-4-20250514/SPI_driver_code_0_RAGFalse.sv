module SPI_driver(
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] data_in,
    input  logic       SPI_MISO,
    input  logic       SPI_start,
    output logic       SPI_MOSI,
    output logic       SPI_CLK,
    output logic       SPI_EN,
    output logic [7:0] data_out
);

    // State machine states
    typedef enum logic [1:0] {
        IDLE   = 2'b00,
        LOAD   = 2'b01,
        SHIFT  = 2'b10,
        DONE   = 2'b11
    } state_t;

    state_t current_state, next_state;

    // Internal registers
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [3:0] bit_counter;
    logic [3:0] clk_divider;
    logic       spi_clk_edge;
    logic       tx_latch;

    // Parameters for clock division (adjust as needed)
    parameter CLK_DIV = 4'd4;  // Divide system clock by 4 for SPI clock

    // Clock divider for SPI_CLK generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 4'd0;
        end else if (current_state == SHIFT) begin
            if (clk_divider == CLK_DIV - 1) begin
                clk_divider <= 4'd0;
            end else begin
                clk_divider <= clk_divider + 1'b1;
            end
        end else begin
            clk_divider <= 4'd0;
        end
    end

    // Generate SPI clock edge signal
    assign spi_clk_edge = (clk_divider == CLK_DIV/2 - 1) || (clk_divider == CLK_DIV - 1);

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = LOAD;
                end
            end
            LOAD: begin
                next_state = SHIFT;
            end
            SHIFT: begin
                if (bit_counter == 4'd8 && clk_divider == CLK_DIV - 1) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
        end else if (current_state == LOAD) begin
            bit_counter <= 4'd0;
        end else if (current_state == SHIFT && clk_divider == CLK_DIV - 1) begin
            bit_counter <= bit_counter + 1'b1;
        end
    end

    // Shift registers and data handling
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'd0;
            rx_shift_reg <= 8'd0;
            tx_latch <= 1'b0;
        end else begin
            case (current_state)
                LOAD: begin
                    tx_shift_reg <= data_in;
                    rx_shift_reg <= 8'd0;
                end
                SHIFT: begin
                    if (spi_clk_edge && clk_divider == CLK_DIV/2 - 1) begin
                        // Sample on first edge (CPHA=1)
                        rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
                    end else if (spi_clk_edge && clk_divider == CLK_DIV - 1) begin
                        // Shift on second edge (CPHA=1)
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                        tx_latch <= tx_shift_reg[6];
                    end
                end
            endcase
        end
    end

    // Output assignments
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= 1'b1;  // CPOL=1: idle high
            SPI_EN <= 1'b1;   // Active low chip select
            data_out <= 8'd0;
        end else begin
            case (current_state)
                IDLE: begin
                    SPI_CLK <= 1'b1;  // CPOL=1: idle high
                    SPI_EN <= 1'b1;
                end
                LOAD: begin
                    SPI_EN <= 1'b0;  // Assert chip select
                end
                SHIFT: begin
                    // Toggle clock for CPOL=1
                    if (clk_divider < CLK_DIV/2) begin
                        SPI_CLK <= 1'b0;  // First half: low
                    end else begin
                        SPI_CLK <= 1'b1;  // Second half: high
                    end
                end
                DONE: begin
                    SPI_CLK <= 1'b1;  // Return to idle high
                    SPI_EN <= 1'b1;   // Deassert chip select
                    data_out <= rx_shift_reg;
                end
            endcase
        end
    end

    // MOSI output - update on second edge for CPHA=1
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_MOSI <= 1'b0;
        end else if (current_state == LOAD) begin
            SPI_MOSI <= data_in[7];  // Prepare first bit
        end else if (current_state == SHIFT && clk_divider == CLK_DIV - 1 && bit_counter < 4'd8) begin
            SPI_MOSI <= tx_latch;
        end
    end

endmodule