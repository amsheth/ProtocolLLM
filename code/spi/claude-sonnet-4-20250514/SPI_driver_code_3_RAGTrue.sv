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
    // CPOL=0: Clock idle state is low
    // CPHA=0: Data is sampled on the first (rising) edge and shifted on the falling edge
    
    // State machine states
    typedef enum logic [2:0] {
        IDLE    = 3'b000,
        START   = 3'b001,
        TRANSFER = 3'b010,
        FINISH  = 3'b011
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [7:0] shift_reg_tx;    // Transmit shift register
    logic [7:0] shift_reg_rx;    // Receive shift register
    logic [3:0] bit_counter;     // Counts bits transferred (0-7)
    logic [3:0] clk_divider;     // Clock divider for SPI clock generation
    logic spi_clk_en;            // SPI clock enable
    logic spi_clk_internal;      // Internal SPI clock
    logic transfer_complete;     // Transfer completion flag
    
    // Clock divider - generates SPI clock at 1/16 of system clock
    // Adjust this value based on your timing requirements
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 4'b0000;
        end else begin
            if (current_state == TRANSFER) begin
                clk_divider <= clk_divider + 1;
            end else begin
                clk_divider <= 4'b0000;
            end
        end
    end
    
    // SPI clock generation (CPOL=0: idle low, CPHA=0: sample on rising edge)
    assign spi_clk_en = (clk_divider == 4'b0111) || (clk_divider == 4'b1111);
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_internal <= 1'b0;  // CPOL=0: idle state is low
        end else begin
            if (current_state == TRANSFER && spi_clk_en) begin
                spi_clk_internal <= ~spi_clk_internal;
            end else if (current_state == IDLE) begin
                spi_clk_internal <= 1'b0;  // Return to idle state
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
        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = START;
                end else begin
                    next_state = IDLE;
                end
            end
            
            START: begin
                next_state = TRANSFER;
            end
            
            TRANSFER: begin
                if (transfer_complete) begin
                    next_state = FINISH;
                end else begin
                    next_state = TRANSFER;
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
    
    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'b0000;
        end else begin
            case (current_state)
                START: begin
                    bit_counter <= 4'b0000;
                end
                
                TRANSFER: begin
                    // Increment on rising edge of SPI clock (CPHA=0)
                    if (spi_clk_en && spi_clk_internal == 1'b0) begin
                        bit_counter <= bit_counter + 1;
                    end
                end
                
                default: begin
                    bit_counter <= 4'b0000;
                end
            endcase
        end
    end
    
    // Transfer complete flag
    assign transfer_complete = (bit_counter == 4'b1000) && (clk_divider == 4'b1111);
    
    // Transmit shift register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg_tx <= 8'b00000000;
        end else begin
            case (current_state)
                START: begin
                    shift_reg_tx <= data_in;  // Load data to transmit
                end
                
                TRANSFER: begin
                    // Shift on falling edge of SPI clock (CPHA=0)
                    if (spi_clk_en && spi_clk_internal == 1'b1) begin
                        shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};  // MSB first
                    end
                end
                
                default: begin
                    shift_reg_tx <= shift_reg_tx;
                end
            endcase
        end
    end
    
    // Receive shift register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg_rx <= 8'b00000000;
        end else begin
            case (current_state)
                START: begin
                    shift_reg_rx <= 8'b00000000;
                end
                
                TRANSFER: begin
                    // Sample on rising edge of SPI clock (CPHA=0)
                    if (spi_clk_en && spi_clk_internal == 1'b0) begin
                        shift_reg_rx <= {shift_reg_rx[6:0], SPI_MISO};  // MSB first
                    end
                end
                
                default: begin
                    shift_reg_rx <= shift_reg_rx;
                end
            endcase
        end
    end
    
    // Output assignments
    assign SPI_CLK = (current_state == TRANSFER) ? spi_clk_internal : 1'b0;
    assign SPI_MOSI = shift_reg_tx[7];  // MSB first transmission
    assign SPI_EN = (current_state == TRANSFER) ? 1'b1 : 1'b0;  // Active high chip select
    assign data_out = (current_state == FINISH) ? shift_reg_rx : 8'b00000000;

endmodule