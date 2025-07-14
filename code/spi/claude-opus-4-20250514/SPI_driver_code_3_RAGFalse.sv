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
    logic [7:0] shift_reg_out;  // Shift register for output data
    logic [7:0] shift_reg_in;   // Shift register for input data
    logic [3:0] bit_counter;     // Counter for bits (0-7)
    logic       spi_clk_reg;     // Internal SPI clock register
    logic       clk_enable;      // Enable for clock generation

    // Clock divider counter (adjust for desired SPI frequency)
    logic [3:0] clk_divider;
    parameter CLK_DIV = 4'd4;    // Divide system clock by 4 for SPI clock

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
                if (SPI_start)
                    next_state = LOAD;
            end
            
            LOAD: begin
                next_state = SHIFT;
            end
            
            SHIFT: begin
                if (bit_counter == 4'd8 && clk_divider == CLK_DIV - 1'b1)
                    next_state = DONE;
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
            bit_counter <= 4'd0;
        end else begin
            if (current_state == SHIFT) begin
                if (clk_divider == CLK_DIV - 1'b1) begin
                    clk_divider <= 4'd0;
                    if (spi_clk_reg == 1'b1) begin  // Count on falling edge of SPI_CLK
                        bit_counter <= bit_counter + 1'b1;
                    end
                end else begin
                    clk_divider <= clk_divider + 1'b1;
                end
            end else begin
                clk_divider <= 4'd0;
                bit_counter <= 4'd0;
            end
        end
    end

    // SPI clock generation (CPOL=0: idle low)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_reg <= 1'b0;
        end else begin
            if (current_state == SHIFT) begin
                if (clk_divider == (CLK_DIV >> 1) - 1'b1)
                    spi_clk_reg <= 1'b1;
                else if (clk_divider == CLK_DIV - 1'b1)
                    spi_clk_reg <= 1'b0;
            end else begin
                spi_clk_reg <= 1'b0;  // CPOL=0: idle low
            end
        end
    end

    // Shift registers and data handling
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg_out <= 8'd0;
            shift_reg_in  <= 8'd0;
        end else begin
            case (current_state)
                LOAD: begin
                    shift_reg_out <= data_in;
                    shift_reg_in  <= 8'd0;
                end
                
                SHIFT: begin
                    // CPHA=0: Sample on leading (rising) edge, shift on trailing (falling) edge
                    if (clk_divider == (CLK_DIV >> 1) - 1'b1) begin
                        // Sample MISO on rising edge of SPI_CLK
                        shift_reg_in <= {shift_reg_in[6:0], SPI_MISO};
                    end
                    else if (clk_divider == CLK_DIV - 1'b1) begin
                        // Shift out data on falling edge of SPI_CLK
                        shift_reg_out <= {shift_reg_out[6:0], 1'b0};
                    end
                end
            endcase
        end
    end

    // Output assignments
    assign SPI_CLK = spi_clk_reg;
    assign SPI_EN = (current_state != IDLE);  // Active during transmission
    assign SPI_MOSI = shift_reg_out[7];       // MSB first

    // Capture received data
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'd0;
        end else begin
            if (current_state == DONE) begin
                data_out <= shift_reg_in;
            end
        end
    end

endmodule