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

    // Parameters for CPOL=0, CPHA=0
    parameter CPOL = 1'b0;  // Clock polarity: idle state is low
    parameter CPHA = 1'b0;  // Clock phase: data captured on first edge, shifted on second edge
    parameter CLK_DIV = 4;  // Clock divider to generate SPI clock (adjust as needed)
    
    // State machine states
    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        START   = 3'b001,
        ACTIVE  = 3'b010,
        FINISH  = 3'b011
    } spi_state_t;
    
    // Internal signals
    spi_state_t current_state, next_state;
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [3:0] bit_counter;
    logic [3:0] clk_counter;
    logic spi_clk_en;
    logic spi_clk_internal;
    logic data_valid;
    
    // Clock generation for SPI
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 4'b0;
            spi_clk_internal <= CPOL;  // Initialize to idle state (CPOL=0 means idle low)
        end else if (spi_clk_en) begin
            if (clk_counter == (CLK_DIV/2 - 1)) begin
                clk_counter <= 4'b0;
                spi_clk_internal <= ~spi_clk_internal;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end else begin
            clk_counter <= 4'b0;
            spi_clk_internal <= CPOL;  // Return to idle state
        end
    end
    
    // State machine - sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // State machine - combinational logic
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
                if (bit_counter == 4'b1111 && clk_counter == (CLK_DIV/2 - 1) && spi_clk_internal == 1'b1) begin
                    next_state = FINISH;
                end
            end
            
            FINISH: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Control signals generation
    always_comb begin
        case (current_state)
            IDLE: begin
                spi_clk_en = 1'b0;
                SPI_EN = 1'b0;
            end
            
            START: begin
                spi_clk_en = 1'b1;
                SPI_EN = 1'b1;
            end
            
            ACTIVE: begin
                spi_clk_en = 1'b1;
                SPI_EN = 1'b1;
            end
            
            FINISH: begin
                spi_clk_en = 1'b0;
                SPI_EN = 1'b0;
            end
            
            default: begin
                spi_clk_en = 1'b0;
                SPI_EN = 1'b0;
            end
        endcase
    end
    
    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'b0;
        end else if (current_state == START) begin
            bit_counter <= 4'b0;
        end else if (current_state == ACTIVE && clk_counter == (CLK_DIV/2 - 1) && spi_clk_internal == 1'b1) begin
            bit_counter <= bit_counter + 1;
        end
    end
    
    // Shift registers for TX and RX
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'b0;
            rx_shift_reg <= 8'b0;
        end else if (current_state == START) begin
            // Load new data to transmit
            tx_shift_reg <= data_in;
            rx_shift_reg <= 8'b0;
        end else if (current_state == ACTIVE && clk_counter == (CLK_DIV/2 - 1)) begin
            if (spi_clk_internal == 1'b0) begin
                // Rising edge of SPI clock - shift out data (CPHA=0)
                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
            end else begin
                // Falling edge of SPI clock - shift in data (CPHA=0)
                rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
            end
        end
    end
    
    // Output data register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'b0;
            data_valid <= 1'b0;
        end else if (current_state == FINISH) begin
            data_out <= rx_shift_reg;
            data_valid <= 1'b1;
        end else if (current_state == IDLE) begin
            data_valid <= 1'b0;
        end
    end
    
    // Output assignments
    assign SPI_CLK = spi_clk_internal;
    assign SPI_MOSI = tx_shift_reg[7];  // MSB first transmission
    
endmodule