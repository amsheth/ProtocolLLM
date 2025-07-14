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

    // Parameters for CPOL=0, CPHA=1
    // CPOL=0: Clock idle state is low
    // CPHA=1: Data is sampled on the rising edge, shifted on falling edge
    
    // State machine states
    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        SETUP   = 3'b001,
        SHIFT   = 3'b010,
        DONE    = 3'b011
    } spi_state_t;
    
    spi_state_t current_state, next_state;
    
    // Internal registers
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [3:0] bit_counter;
    logic [3:0] clk_divider;
    logic spi_clk_enable;
    logic spi_clk_internal;
    logic data_valid;
    
    // Clock generation (divide by 8 for example)
    // Adjust this divider based on your system clock frequency
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 4'b0000;
        end else if (current_state == SHIFT) begin
            clk_divider <= clk_divider + 1'b1;
        end else begin
            clk_divider <= 4'b0000;
        end
    end
    
    // Generate SPI clock enable signal
    assign spi_clk_enable = (clk_divider == 4'b0111); // Clock enable every 8 system clocks
    
    // SPI Clock generation (CPOL=0: idle low)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_internal <= 1'b0;
        end else if (current_state == IDLE || current_state == DONE) begin
            spi_clk_internal <= 1'b0; // Idle low for CPOL=0
        end else if (current_state == SHIFT && spi_clk_enable) begin
            spi_clk_internal <= ~spi_clk_internal;
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
                    next_state = SETUP;
                end
            end
            
            SETUP: begin
                next_state = SHIFT;
            end
            
            SHIFT: begin
                if (bit_counter == 4'd8 && spi_clk_enable && spi_clk_internal == 1'b1) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
        end else if (current_state == SETUP) begin
            bit_counter <= 4'd0;
        end else if (current_state == SHIFT && spi_clk_enable && spi_clk_internal == 1'b1) begin
            // Count on rising edge of SPI clock (CPHA=1: sample on rising edge)
            bit_counter <= bit_counter + 1'b1;
        end
    end
    
    // Shift registers for TX and RX
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'b0;
            rx_shift_reg <= 8'b0;
        end else if (current_state == SETUP) begin
            tx_shift_reg <= data_in; // Load data to transmit
            rx_shift_reg <= 8'b0;
        end else if (current_state == SHIFT && spi_clk_enable) begin
            if (spi_clk_internal == 1'b0) begin
                // Falling edge: shift out data (CPHA=1)
                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
            end else begin
                // Rising edge: sample input data (CPHA=1)
                rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
            end
        end
    end
    
    // Data valid flag
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_valid <= 1'b0;
        end else if (current_state == DONE) begin
            data_valid <= 1'b1;
        end else if (current_state == SETUP) begin
            data_valid <= 1'b0;
        end
    end
    
    // Output assignments
    assign SPI_CLK = spi_clk_internal;
    assign SPI_MOSI = tx_shift_reg[7]; // MSB first
    assign SPI_EN = (current_state == SHIFT || current_state == SETUP); // Active during transfer
    assign data_out = data_valid ? rx_shift_reg : 8'b0;

endmodule