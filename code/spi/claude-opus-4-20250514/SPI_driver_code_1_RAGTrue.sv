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

    // State machine states
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        TRANSFER = 2'b01,
        DONE = 2'b10
    } state_t;

    state_t current_state, next_state;

    // Internal registers
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [3:0] bit_counter;
    logic [3:0] clk_divider;
    logic sclk_int;
    logic transfer_done;

    // Clock divider parameter (adjust based on system clock)
    parameter CLK_DIV = 4'd8;  // Divide by 8 for SPI clock

    // CPOL = 1, CPHA = 0 configuration
    // Clock idle high, sample on falling edge, shift on rising edge

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
                    next_state = TRANSFER;
                end
            end
            
            TRANSFER: begin
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

    // Clock generation and divider
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 4'd0;
            sclk_int <= 1'b1;  // CPOL = 1, idle high
        end else if (current_state == TRANSFER) begin
            if (clk_divider == CLK_DIV - 1) begin
                clk_divider <= 4'd0;
                sclk_int <= ~sclk_int;
            end else begin
                clk_divider <= clk_divider + 1'b1;
            end
        end else begin
            clk_divider <= 4'd0;
            sclk_int <= 1'b1;  // Return to idle high
        end
    end

    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
            transfer_done <= 1'b0;
        end else if (current_state == IDLE) begin
            bit_counter <= 4'd0;
            transfer_done <= 1'b0;
        end else if (current_state == TRANSFER) begin
            // Count on falling edge of sclk_int (CPHA = 0)
            if (clk_divider == CLK_DIV - 1 && sclk_int == 1'b1) begin
                if (bit_counter == 4'd7) begin
                    transfer_done <= 1'b1;
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end
            end
        end
    end

    // TX shift register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'd0;
        end else if (current_state == IDLE && SPI_start) begin
            tx_shift_reg <= data_in;  // Load data
        end else if (current_state == TRANSFER) begin
            // Shift on rising edge of sclk_int (CPHA = 0)
            if (clk_divider == CLK_DIV - 1 && sclk_int == 1'b0) begin
                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};  // MSB first
            end
        end
    end

    // RX shift register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_shift_reg <= 8'd0;
        end else if (current_state == TRANSFER) begin
            // Sample on falling edge of sclk_int (CPHA = 0)
            if (clk_divider == CLK_DIV - 1 && sclk_int == 1'b1) begin
                rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};  // MSB first
            end
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
    assign SPI_CLK = (current_state == TRANSFER) ? sclk_int : 1'b1;  // CPOL = 1
    assign SPI_MOSI = tx_shift_reg[7];  // MSB first
    assign SPI_EN = (current_state != IDLE);  // Active during transfer

endmodule