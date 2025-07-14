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
        IDLE    = 2'b00,
        LOAD    = 2'b01,
        SHIFT   = 2'b10,
        DONE    = 2'b11
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [7:0] shift_reg_tx;  // Transmit shift register
    logic [7:0] shift_reg_rx;  // Receive shift register
    logic [2:0] bit_counter;    // Counts bits (0-7)
    logic       spi_clk_reg;    // Internal SPI clock register
    logic       first_edge;     // Tracks first edge in CPHA=1
    
    // Clock divider counter (adjust for desired SPI clock frequency)
    logic [3:0] clk_divider;
    parameter CLK_DIV = 4'd4;   // Divide system clock by 4
    
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
                if (bit_counter == 3'd7 && clk_divider == CLK_DIV-1 && !spi_clk_reg) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Clock divider and bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 4'd0;
            bit_counter <= 3'd0;
            first_edge  <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    clk_divider <= 4'd0;
                    bit_counter <= 3'd0;
                    first_edge  <= 1'b0;
                end
                
                LOAD: begin
                    clk_divider <= 4'd0;
                    bit_counter <= 3'd0;
                    first_edge  <= 1'b1;  // Set for first edge handling
                end
                
                SHIFT: begin
                    if (clk_divider == CLK_DIV-1) begin
                        clk_divider <= 4'd0;
                        
                        // For CPHA=1, increment bit counter on falling edge
                        if (!spi_clk_reg) begin
                            if (!first_edge) begin
                                bit_counter <= bit_counter + 1'b1;
                            end else begin
                                first_edge <= 1'b0;
                            end
                        end
                    end else begin
                        clk_divider <= clk_divider + 1'b1;
                    end
                end
                
                default: begin
                    clk_divider <= 4'd0;
                    bit_counter <= 3'd0;
                    first_edge  <= 1'b0;
                end
            endcase
        end
    end
    
    // SPI clock generation (CPOL=0)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_reg <= 1'b0;  // CPOL=0: clock idle low
        end else begin
            case (current_state)
                SHIFT: begin
                    if (clk_divider == CLK_DIV-1) begin
                        spi_clk_reg <= ~spi_clk_reg;
                    end
                end
                default: begin
                    spi_clk_reg <= 1'b0;  // CPOL=0: clock idle low
                end
            endcase
        end
    end
    
    // Shift registers for TX and RX
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg_tx <= 8'd0;
            shift_reg_rx <= 8'd0;
        end else begin
            case (current_state)
                LOAD: begin
                    shift_reg_tx <= data_in;
                    shift_reg_rx <= 8'd0;
                end
                
                SHIFT: begin
                    if (clk_divider == CLK_DIV-1) begin
                        // CPHA=1: Sample on rising edge, shift on falling edge
                        if (spi_clk_reg) begin  // Rising edge
                            shift_reg_rx <= {shift_reg_rx[6:0], SPI_MISO};
                        end else begin  // Falling edge
                            if (!first_edge) begin
                                shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};
                            end
                        end
                    end
                end
            endcase
        end
    end
    
    // Output data register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'd0;
        end else begin
            if (current_state == DONE) begin
                data_out <= shift_reg_rx;
            end
        end
    end
    
    // Output assignments
    assign SPI_CLK = spi_clk_reg;
    assign SPI_MOSI = shift_reg_tx[7];  // MSB first
    assign SPI_EN = (current_state == IDLE) ? 1'b1 : 1'b0;  // Active low chip select

endmodule