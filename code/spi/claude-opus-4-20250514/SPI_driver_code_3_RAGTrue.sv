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
    logic [3:0] bit_counter;   // Count bits (0-7)
    logic [3:0] clk_divider;   // Clock divider counter
    logic       sclk_enable;   // Enable for generating SPI_CLK
    logic       transfer_done; // Flag for transfer completion

    // Clock divider parameter (adjust for desired SPI clock rate)
    parameter CLK_DIV = 4'd8;  // Divide system clock by 8

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

    // Clock divider for SPI clock generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 4'd0;
            sclk_enable <= 1'b0;
        end else if (current_state == SHIFT) begin
            if (clk_divider == CLK_DIV - 1) begin
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

    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
        end else if (current_state == LOAD) begin
            bit_counter <= 4'd0;
        end else if (current_state == SHIFT && sclk_enable && ~SPI_CLK) begin
            if (bit_counter == 4'd7) begin
                bit_counter <= 4'd0;
            end else begin
                bit_counter <= bit_counter + 1'b1;
            end
        end
    end

    // Transfer done detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            transfer_done <= 1'b0;
        end else if (current_state == SHIFT && bit_counter == 4'd7 && sclk_enable && ~SPI_CLK) begin
            transfer_done <= 1'b1;
        end else begin
            transfer_done <= 1'b0;
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
                    if (sclk_enable) begin
                        if (SPI_CLK) begin  // CPHA=0: Sample on rising edge
                            shift_reg_rx <= {shift_reg_rx[6:0], SPI_MISO};
                        end else begin      // CPHA=0: Shift on falling edge
                            shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};
                        end
                    end
                end
            endcase
        end
    end

    // SPI Clock generation (CPOL=0: idle low)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= 1'b0;
        end else if (current_state == SHIFT && sclk_enable) begin
            SPI_CLK <= ~SPI_CLK;
        end else begin
            SPI_CLK <= 1'b0;  // CPOL=0: Clock idles low
        end
    end

    // Output assignments
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_EN <= 1'b1;     // Active low chip select (idle high)
            data_out <= 8'd0;
        end else begin
            case (current_state)
                IDLE: begin
                    SPI_EN <= 1'b1;  // Deassert chip select
                end
                
                LOAD, SHIFT: begin
                    SPI_EN <= 1'b0;  // Assert chip select (active low)
                end
                
                DONE: begin
                    SPI_EN <= 1'b1;  // Deassert chip select
                    data_out <= shift_reg_rx;  // Latch received data
                end
            endcase
        end
    end

    // MOSI output (MSB first)
    assign SPI_MOSI = shift_reg_tx[7];

endmodule