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

    // Parameters for CPOL=1, CPHA=0
    // CPOL=1: Clock idle state is high
    // CPHA=0: Data is sampled on the first (rising) edge and shifted on the second (falling) edge
    
    // Internal signals
    logic [3:0] bit_counter;
    logic [3:0] clk_counter;
    logic [7:0] shift_reg_tx;
    logic [7:0] shift_reg_rx;
    logic spi_clk_int;
    logic transfer_active;
    logic clk_enable;
    
    // State machine states
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        TRANSFER = 2'b01,
        COMPLETE = 2'b10
    } state_t;
    
    state_t current_state, next_state;
    
    // Clock divider to generate SPI clock (divide by 8 for example)
    // You can adjust this based on your system clock frequency requirements
    parameter CLK_DIV = 4;
    
    // Clock generation and division
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 0;
            spi_clk_int <= 1'b1;  // CPOL=1, so idle state is high
        end else if (transfer_active) begin
            if (clk_counter == CLK_DIV - 1) begin
                clk_counter <= 0;
                spi_clk_int <= ~spi_clk_int;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end else begin
            clk_counter <= 0;
            spi_clk_int <= 1'b1;  // Return to idle state (high for CPOL=1)
        end
    end
    
    // Clock enable generation - generates pulse at the beginning of each SPI clock period
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_enable <= 1'b0;
        end else begin
            clk_enable <= (clk_counter == CLK_DIV - 1) && transfer_active;
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
                    next_state = TRANSFER;
                end else begin
                    next_state = IDLE;
                end
            end
            
            TRANSFER: begin
                if (bit_counter == 4'd8 && clk_enable && spi_clk_int) begin
                    next_state = COMPLETE;
                end else begin
                    next_state = TRANSFER;
                end
            end
            
            COMPLETE: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Transfer active signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            transfer_active <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    transfer_active <= SPI_start;
                end
                TRANSFER: begin
                    transfer_active <= 1'b1;
                end
                COMPLETE: begin
                    transfer_active <= 1'b0;
                end
                default: begin
                    transfer_active <= 1'b0;
                end
            endcase
        end
    end
    
    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
        end else begin
            case (current_state)
                IDLE: begin
                    bit_counter <= 4'd0;
                end
                TRANSFER: begin
                    if (clk_enable && spi_clk_int) begin  // Count on rising edge for CPHA=0
                        bit_counter <= bit_counter + 1;
                    end
                end
                COMPLETE: begin
                    bit_counter <= 4'd0;
                end
                default: begin
                    bit_counter <= 4'd0;
                end
            endcase
        end
    end
    
    // Shift registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg_tx <= 8'd0;
            shift_reg_rx <= 8'd0;
        end else begin
            case (current_state)
                IDLE: begin
                    if (SPI_start) begin
                        shift_reg_tx <= data_in;  // Load data to transmit
                        shift_reg_rx <= 8'd0;
                    end
                end
                TRANSFER: begin
                    if (clk_enable) begin
                        if (spi_clk_int) begin  // Rising edge - sample MISO (CPHA=0)
                            shift_reg_rx <= {shift_reg_rx[6:0], SPI_MISO};
                        end else begin  // Falling edge - shift out next bit
                            shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};
                        end
                    end
                end
                default: begin
                    // Keep current values
                end
            endcase
        end
    end
    
    // Output assignments
    assign SPI_CLK = transfer_active ? spi_clk_int : 1'b1;  // CPOL=1, idle high
    assign SPI_MOSI = transfer_active ? shift_reg_tx[7] : 1'b0;  // MSB first
    assign SPI_EN = transfer_active;  // Chip select (active high)
    assign data_out = (current_state == COMPLETE) ? shift_reg_rx : 8'd0;

endmodule