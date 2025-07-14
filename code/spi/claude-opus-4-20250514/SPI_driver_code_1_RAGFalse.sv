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

    // Parameters
    parameter CLK_DIV = 4;  // Clock divider (SPI_CLK = clk/CLK_DIV)
    
    // State machine states
    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        ACTIVE  = 2'b01,
        DONE    = 2'b10
    } state_t;
    
    state_t state, next_state;
    
    // Internal signals
    logic [7:0] tx_data_reg;
    logic [7:0] rx_data_reg;
    logic [2:0] bit_counter;
    logic [$clog2(CLK_DIV)-1:0] clk_divider;
    logic spi_clk_edge;
    logic transfer_done;
    
    // Clock divider for SPI_CLK generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= '0;
        end else if (state == ACTIVE) begin
            if (clk_divider == CLK_DIV/2 - 1) begin
                clk_divider <= '0;
            end else begin
                clk_divider <= clk_divider + 1'b1;
            end
        end else begin
            clk_divider <= '0;
        end
    end
    
    // Generate SPI clock edge signal
    assign spi_clk_edge = (clk_divider == CLK_DIV/2 - 1);
    
    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = ACTIVE;
                end
            end
            ACTIVE: begin
                if (transfer_done) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end
    
    // Bit counter and transfer control
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 3'b0;
            transfer_done <= 1'b0;
        end else begin
            if (state == IDLE) begin
                bit_counter <= 3'b0;
                transfer_done <= 1'b0;
            end else if (state == ACTIVE && spi_clk_edge) begin
                if (bit_counter == 3'd7) begin
                    transfer_done <= 1'b1;
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end
            end
        end
    end
    
    // Data registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_data_reg <= 8'h00;
            rx_data_reg <= 8'h00;
        end else begin
            if (state == IDLE && SPI_start) begin
                tx_data_reg <= data_in;
            end else if (state == ACTIVE && spi_clk_edge) begin
                // CPHA=0: Sample on leading edge (falling edge for CPOL=1)
                rx_data_reg <= {rx_data_reg[6:0], SPI_MISO};
                // Shift tx data for next bit
                tx_data_reg <= {tx_data_reg[6:0], 1'b0};
            end
        end
    end
    
    // SPI_CLK generation (CPOL=1: idle high)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= 1'b1;  // CPOL=1: idle high
        end else begin
            if (state == ACTIVE) begin
                if (clk_divider < CLK_DIV/2) begin
                    SPI_CLK <= 1'b0;  // Low phase
                end else begin
                    SPI_CLK <= 1'b1;  // High phase
                end
            end else begin
                SPI_CLK <= 1'b1;  // CPOL=1: idle high
            end
        end
    end
    
    // Output assignments
    assign SPI_MOSI = (state == ACTIVE) ? tx_data_reg[7] : 1'b0;
    assign SPI_EN = (state != IDLE);
    assign data_out = rx_data_reg;

endmodule