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
    logic       sclk_enable;
    logic       sclk_reg;
    
    // Clock divider for SPI clock generation
    parameter CLK_DIV = 4'd4; // Divide system clock by 4 for SPI clock

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
                if (bit_counter == 4'd0 && clk_divider == CLK_DIV-1) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    // Clock divider for SPI clock generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 4'd0;
            sclk_enable <= 1'b0;
        end else if (current_state == SHIFT) begin
            if (clk_divider == CLK_DIV-1) begin
                clk_divider <= 4'd0;
                sclk_enable <= 1'b1;
            end else begin
                clk_divider <= clk_divider + 1'b1;
                sclk_enable <= 1'b0;
            end
        end else begin
            clk_divider <= 4'd0;
            sclk_enable <= 1'b0;
        end
    end

    // SPI clock generation (CPOL=0)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_reg <= 1'b0;
        end else if (current_state == SHIFT) begin
            if (sclk_enable) begin
                sclk_reg <= ~sclk_reg;
            end
        end else begin
            sclk_reg <= 1'b0; // CPOL=0, idle low
        end
    end

    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd8;
        end else if (current_state == LOAD) begin
            bit_counter <= 4'd8;
        end else if (current_state == SHIFT && sclk_enable && sclk_reg) begin
            // Decrement on falling edge of SPI clock
            bit_counter <= bit_counter - 1'b1;
        end
    end

    // TX shift register and MOSI output (CPHA=1)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'd0;
        end else if (current_state == LOAD) begin
            tx_shift_reg <= data_in;
        end else if (current_state == SHIFT && sclk_enable && sclk_reg) begin
            // Shift on falling edge of SPI clock (CPHA=1)
            tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
        end
    end

    // RX shift register (CPHA=1)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_shift_reg <= 8'd0;
        end else if (current_state == SHIFT && sclk_enable && !sclk_reg) begin
            // Sample on rising edge of SPI clock (CPHA=1)
            rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
        end
    end

    // Data output register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'd0;
        end else if (current_state == DONE) begin
            data_out <= rx_shift_reg;
        end
    end

    // Output assignments
    assign SPI_CLK = sclk_reg;
    assign SPI_MOSI = tx_shift_reg[7]; // MSB first
    assign SPI_EN = (current_state != IDLE); // Active during transmission

endmodule