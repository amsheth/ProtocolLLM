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
    logic       sclk_int;
    logic       transfer_done;
    
    // Clock divider for SPI clock generation
    parameter CLK_DIV = 4'd4; // Adjust based on system clock to SPI clock ratio
    
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
                    next_state = LOAD;
                end
            end
            
            LOAD: begin
                next_state = SHIFT;
            end
            
            SHIFT: begin
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
    
    // Clock divider for SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 4'd0;
            sclk_int <= 1'b1; // CPOL=1, idle high
        end else if (current_state == SHIFT) begin
            if (clk_divider == CLK_DIV - 1) begin
                clk_divider <= 4'd0;
                sclk_int <= ~sclk_int;
            end else begin
                clk_divider <= clk_divider + 1'b1;
            end
        end else begin
            clk_divider <= 4'd0;
            sclk_int <= 1'b1; // CPOL=1, idle high
        end
    end
    
    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
        end else if (current_state == LOAD) begin
            bit_counter <= 4'd0;
        end else if (current_state == SHIFT && clk_divider == CLK_DIV - 1 && sclk_int == 1'b0) begin
            // Count on falling edge of sclk when CPHA=1
            bit_counter <= bit_counter + 1'b1;
        end
    end
    
    // Transfer done signal
    assign transfer_done = (bit_counter == 4'd8);
    
    // Shift registers for TX and RX
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'd0;
            rx_shift_reg <= 8'd0;
        end else begin
            case (current_state)
                LOAD: begin
                    tx_shift_reg <= data_in;
                    rx_shift_reg <= 8'd0;
                end
                
                SHIFT: begin
                    // CPHA=1: Sample on first edge (falling when CPOL=1), shift on second edge (rising)
                    if (clk_divider == CLK_DIV - 1) begin
                        if (sclk_int == 1'b1) begin
                            // Falling edge of sclk - sample MISO
                            rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
                        end else begin
                            // Rising edge of sclk - shift out next bit
                            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
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
            data_out <= 8'd0;
        end else if (current_state == DONE) begin
            data_out <= rx_shift_reg;
        end
    end
    
    // SPI output signals
    assign SPI_CLK = (current_state == SHIFT) ? sclk_int : 1'b1; // CPOL=1
    assign SPI_MOSI = tx_shift_reg[7]; // MSB first
    assign SPI_EN = ~(current_state == SHIFT || current_state == LOAD); // Active low enable
    
endmodule