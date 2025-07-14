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

    // Parameters for CPOL=1, CPHA=1
    parameter CPOL = 1'b1;  // Clock polarity: idle high
    parameter CPHA = 1'b1;  // Clock phase: sample on falling edge, shift on rising edge
    parameter CLK_DIV = 4;  // Clock divider (adjust as needed)
    
    // State machine states
    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        START   = 3'b001,
        ACTIVE  = 3'b010,
        DONE    = 3'b011
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [7:0] data_out_reg;
    logic [3:0] bit_counter;
    logic [3:0] clk_counter;
    logic spi_clk_reg;
    logic spi_en_reg;
    logic spi_mosi_reg;
    logic sample_enable;
    logic shift_enable;
    
    // Clock generation counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 4'b0;
        end else if (current_state == ACTIVE) begin
            clk_counter <= clk_counter + 1;
        end else begin
            clk_counter <= 4'b0;
        end
    end
    
    // Generate sample and shift enables
    assign sample_enable = (clk_counter == (CLK_DIV/2 - 1)) && (current_state == ACTIVE);
    assign shift_enable = (clk_counter == (CLK_DIV - 1)) && (current_state == ACTIVE);
    
    // SPI Clock generation (CPOL=1: idle high, CPHA=1: toggle on shift_enable)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_reg <= CPOL;  // Idle state is high for CPOL=1
        end else if (current_state == IDLE || current_state == DONE) begin
            spi_clk_reg <= CPOL;  // Return to idle state
        end else if (shift_enable) begin
            spi_clk_reg <= ~spi_clk_reg;  // Toggle clock
        end
    end
    
    // State machine sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // State machine combinational logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = START;
                end
            end
            
            START: begin
                next_state = ACTIVE;
            end
            
            ACTIVE: begin
                if (bit_counter == 4'd8 && shift_enable) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
        end else if (current_state == START) begin
            bit_counter <= 4'd0;
        end else if (shift_enable && current_state == ACTIVE) begin
            bit_counter <= bit_counter + 1;
        end
    end
    
    // TX shift register (MOSI data)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'b0;
            spi_mosi_reg <= 1'b0;
        end else if (current_state == START) begin
            tx_shift_reg <= data_in;
            spi_mosi_reg <= data_in[7];  // Load first bit
        end else if (shift_enable && current_state == ACTIVE) begin
            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};  // Shift left
            spi_mosi_reg <= tx_shift_reg[6];  // Next bit to transmit
        end
    end
    
    // RX shift register (MISO data) - Sample on falling edge for CPHA=1
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_shift_reg <= 8'b0;
        end else if (current_state == START) begin
            rx_shift_reg <= 8'b0;
        end else if (sample_enable && current_state == ACTIVE) begin
            rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};  // Shift in received bit
        end
    end
    
    // Output data register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out_reg <= 8'b0;
        end else if (current_state == DONE) begin
            data_out_reg <= rx_shift_reg;
        end
    end
    
    // SPI Enable signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_en_reg <= 1'b1;  // Idle high (inactive)
        end else if (current_state == ACTIVE) begin
            spi_en_reg <= 1'b0;  // Active low during transmission
        end else begin
            spi_en_reg <= 1'b1;  // Inactive
        end
    end
    
    // Output assignments
    assign SPI_CLK = spi_clk_reg;
    assign SPI_MOSI = spi_mosi_reg;
    assign SPI_EN = spi_en_reg;
    assign data_out = data_out_reg;

endmodule