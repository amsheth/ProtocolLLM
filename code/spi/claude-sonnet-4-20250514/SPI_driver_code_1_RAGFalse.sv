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
    parameter CPOL = 1;  // Clock polarity: idle state is high
    parameter CPHA = 0;  // Clock phase: data sampled on first edge
    
    // Internal registers and signals
    typedef enum logic [2:0] {
        IDLE,
        ACTIVE,
        DONE
    } state_t;
    
    state_t current_state, next_state;
    
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [3:0] bit_counter;
    logic [7:0] clk_divider;
    logic spi_clk_en;
    logic spi_clk_internal;
    logic data_valid;
    
    // Clock divider for SPI clock generation
    // Adjust the division factor as needed for your application
    parameter CLK_DIV = 8;  // Divide system clock by 8
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 0;
            spi_clk_en <= 0;
        end else begin
            if (current_state == ACTIVE) begin
                if (clk_divider == CLK_DIV/2 - 1) begin
                    clk_divider <= 0;
                    spi_clk_en <= 1;
                end else begin
                    clk_divider <= clk_divider + 1;
                    spi_clk_en <= 0;
                end
            end else begin
                clk_divider <= 0;
                spi_clk_en <= 0;
            end
        end
    end
    
    // SPI clock generation with CPOL=1 (idle high)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_internal <= CPOL;  // Initialize to idle state (high for CPOL=1)
        end else begin
            if (current_state == ACTIVE && spi_clk_en) begin
                spi_clk_internal <= ~spi_clk_internal;
            end else if (current_state == IDLE) begin
                spi_clk_internal <= CPOL;  // Return to idle state
            end
        end
    end
    
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
                    next_state = ACTIVE;
                end
            end
            ACTIVE: begin
                if (bit_counter == 8 && spi_clk_en && spi_clk_internal == CPOL) begin
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
            bit_counter <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    bit_counter <= 0;
                end
                ACTIVE: begin
                    // For CPHA=0, count on the first edge (falling edge when CPOL=1)
                    if (spi_clk_en && spi_clk_internal == 1'b1) begin
                        bit_counter <= bit_counter + 1;
                    end
                end
                DONE: begin
                    bit_counter <= 0;
                end
            endcase
        end
    end
    
    // TX shift register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'h00;
        end else begin
            case (current_state)
                IDLE: begin
                    if (SPI_start) begin
                        tx_shift_reg <= data_in;
                    end
                end
                ACTIVE: begin
                    // For CPHA=0, shift on the first edge (falling edge when CPOL=1)
                    if (spi_clk_en && spi_clk_internal == 1'b1 && bit_counter < 8) begin
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                    end
                end
            endcase
        end
    end
    
    // RX shift register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_shift_reg <= 8'h00;
        end else begin
            case (current_state)
                IDLE: begin
                    rx_shift_reg <= 8'h00;
                end
                ACTIVE: begin
                    // For CPHA=0, sample on the first edge (falling edge when CPOL=1)
                    if (spi_clk_en && spi_clk_internal == 1'b1 && bit_counter < 8) begin
                        rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
                    end
                end
            endcase
        end
    end
    
    // Data valid flag
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_valid <= 0;
        end else begin
            data_valid <= (current_state == DONE);
        end
    end
    
    // Output assignments
    assign SPI_CLK = spi_clk_internal;
    assign SPI_MOSI = tx_shift_reg[7];  // MSB first
    assign SPI_EN = (current_state == ACTIVE);  // Active low chip select
    assign data_out = data_valid ? rx_shift_reg : 8'h00;

endmodule