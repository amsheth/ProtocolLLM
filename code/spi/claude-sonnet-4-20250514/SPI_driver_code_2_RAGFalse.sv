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
    parameter CPOL = 1'b0;  // Clock polarity: idle state is low
    parameter CPHA = 1'b1;  // Clock phase: data captured on rising edge, shifted on falling edge
    
    // Internal signals
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        ACTIVE = 2'b01,
        DONE = 2'b10
    } state_t;
    
    state_t current_state, next_state;
    
    logic [3:0] bit_counter;
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic spi_clk_en;
    logic spi_clk_internal;
    logic clk_div;
    logic [3:0] clk_counter;
    
    // Clock divider for SPI clock generation
    // Divides input clock by 8 to create SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 4'b0;
            clk_div <= 1'b0;
        end else begin
            clk_counter <= clk_counter + 1'b1;
            if (clk_counter == 4'b0111) begin
                clk_div <= ~clk_div;
                clk_counter <= 4'b0;
            end
        end
    end
    
    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end
    
    always_comb begin
        case (current_state)
            IDLE: begin
                if (SPI_start)
                    next_state = ACTIVE;
                else
                    next_state = IDLE;
            end
            
            ACTIVE: begin
                if (bit_counter == 4'b1000)  // 8 bits transmitted
                    next_state = DONE;
                else
                    next_state = ACTIVE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Control signals
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_en <= 1'b0;
            SPI_EN <= 1'b0;
            bit_counter <= 4'b0;
            tx_shift_reg <= 8'b0;
            rx_shift_reg <= 8'b0;
            data_out <= 8'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    spi_clk_en <= 1'b0;
                    SPI_EN <= 1'b0;
                    bit_counter <= 4'b0;
                    if (SPI_start) begin
                        tx_shift_reg <= data_in;
                        rx_shift_reg <= 8'b0;
                    end
                end
                
                ACTIVE: begin
                    spi_clk_en <= 1'b1;
                    SPI_EN <= 1'b1;
                    
                    // For CPHA=1: Data changes on falling edge, sampled on rising edge
                    if (clk_div == 1'b0 && clk_counter == 4'b0111) begin  // Falling edge of SPI clock
                        // Shift out next bit (MSB first)
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                    end
                    
                    if (clk_div == 1'b1 && clk_counter == 4'b0111) begin  // Rising edge of SPI clock
                        // Sample MISO and increment bit counter
                        rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
                
                DONE: begin
                    spi_clk_en <= 1'b0;
                    SPI_EN <= 1'b0;
                    data_out <= rx_shift_reg;
                end
            endcase
        end
    end
    
    // SPI Clock generation
    // CPOL=0: Idle state is low
    // CPHA=1: Data captured on rising edge, shifted on falling edge
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_internal <= CPOL;
        end else begin
            if (spi_clk_en) begin
                if (clk_counter == 4'b0111) begin
                    spi_clk_internal <= clk_div;
                end
            end else begin
                spi_clk_internal <= CPOL;  // Return to idle state
            end
        end
    end
    
    // Output assignments
    assign SPI_CLK = spi_clk_internal;
    assign SPI_MOSI = tx_shift_reg[7];  // MSB first
    
endmodule