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
    parameter CPOL = 1;  // Clock polarity: 1 = idle high
    parameter CPHA = 1;  // Clock phase: 1 = sample on second edge
    parameter CLK_DIVIDER = 8;  // System clock divider for SPI clock
    
    // State machine states
    typedef enum logic [2:0] {
        IDLE,
        START,
        TRANSMIT,
        DONE
    } spi_state_t;
    
    // Internal signals
    spi_state_t current_state, next_state;
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [3:0] bit_counter;
    logic [7:0] clk_counter;
    logic spi_clk_enable;
    logic spi_clk_int;
    logic data_valid;
    logic transfer_complete;
    
    // Clock generation for SPI
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 8'b0;
            spi_clk_int <= CPOL;  // Initialize to idle state based on CPOL
        end else if (spi_clk_enable) begin
            if (clk_counter == CLK_DIVIDER - 1) begin
                clk_counter <= 8'b0;
                spi_clk_int <= ~spi_clk_int;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end else begin
            clk_counter <= 8'b0;
            spi_clk_int <= CPOL;  // Return to idle state
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
                next_state = TRANSMIT;
            end
            
            TRANSMIT: begin
                if (transfer_complete) begin
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
    
    // Bit counter and transfer control
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'b0;
            transfer_complete <= 1'b0;
        end else begin
            case (current_state)
                START: begin
                    bit_counter <= 4'b0;
                    transfer_complete <= 1'b0;
                end
                
                TRANSMIT: begin
                    // For CPHA=1, count on the first edge (sampling edge)
                    if (spi_clk_enable && clk_counter == CLK_DIVIDER - 1) begin
                        if ((CPHA == 1 && spi_clk_int == ~CPOL) || 
                            (CPHA == 0 && spi_clk_int == CPOL)) begin
                            bit_counter <= bit_counter + 1;
                            if (bit_counter == 4'd7) begin
                                transfer_complete <= 1'b1;
                            end
                        end
                    end
                end
                
                default: begin
                    bit_counter <= 4'b0;
                    transfer_complete <= 1'b0;
                end
            endcase
        end
    end
    
    // Shift registers for TX and RX
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'b0;
            rx_shift_reg <= 8'b0;
        end else begin
            case (current_state)
                START: begin
                    tx_shift_reg <= data_in;  // Load data to transmit
                    rx_shift_reg <= 8'b0;
                end
                
                TRANSMIT: begin
                    if (spi_clk_enable && clk_counter == CLK_DIVIDER - 1) begin
                        // For CPHA=1: setup on first edge, sample on second edge
                        if (CPHA == 1) begin
                            if (spi_clk_int == CPOL) begin
                                // Setup edge - shift TX data
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                            end else begin
                                // Sample edge - capture RX data
                                rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
                            end
                        end else begin
                            // For CPHA=0: sample on first edge, setup on second edge
                            if (spi_clk_int == CPOL) begin
                                // Sample edge - capture RX data
                                rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
                            end else begin
                                // Setup edge - shift TX data
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                            end
                        end
                    end
                end
                
                default: begin
                    // Keep current values
                end
            endcase
        end
    end
    
    // Output data register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'b0;
            data_valid <= 1'b0;
        end else if (current_state == DONE) begin
            data_out <= rx_shift_reg;
            data_valid <= 1'b1;
        end else if (current_state == IDLE) begin
            data_valid <= 1'b0;
        end
    end
    
    // Output assignments
    assign SPI_CLK = spi_clk_int;
    assign SPI_MOSI = tx_shift_reg[7];  // MSB first transmission
    assign SPI_EN = (current_state == TRANSMIT) ? 1'b1 : 1'b0;
    assign spi_clk_enable = (current_state == TRANSMIT) ? 1'b1 : 1'b0;

endmodule