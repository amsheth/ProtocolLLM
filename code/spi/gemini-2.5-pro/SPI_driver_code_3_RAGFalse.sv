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

    // Parameter for SPI clock generation.
    // The generated SPI_CLK frequency will be the system clk frequency
    // divided by CLK_DIVIDER. For a 50% duty cycle, CLK_DIVIDER must be even.
    // Example: clk=50MHz, SPI_CLK=1MHz => CLK_DIVIDER = 50
    parameter CLK_DIVIDER = 8;

    // Internal state machine definition
    typedef enum logic [1:0] { S_IDLE, S_TRANSFER, S_CLEANUP } state_t;
    state_t state;

    // Internal registers for data shifting and counters
    logic [$clog2(CLK_DIVIDER)-1:0] clk_div_cnt;
    logic [2:0] bit_cnt;
    logic [7:0] tx_reg;
    logic [7:0] rx_reg;
    logic [7:0] data_out_reg;

    // Single process for state machine and data path logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all signals and registers to a known default state
            state <= S_IDLE;
            SPI_EN <= 1'b1;
            SPI_MOSI <= 1'b0;
            SPI_CLK <= 1'b0; // For CPOL=0, idle clock is low
            data_out_reg <= 8'h00;
            clk_div_cnt <= 0;
            bit_cnt <= 0;
            tx_reg <= 8'h00;
            rx_reg <= 8'h00;
        end else begin
            case (state)
                S_IDLE: begin
                    // In idle state, keep outputs at their inactive levels
                    SPI_EN <= 1'b1;
                    SPI_CLK <= 1'b0;
                    // Reset counters for the next transaction
                    bit_cnt <= 0;
                    clk_div_cnt <= 0;

                    // Wait for the start signal
                    if (SPI_start) begin
                        // Load input data into the transmit register
                        tx_reg <= data_in;
                        // Assert the slave enable (active low)
                        SPI_EN <= 1'b0;
                        // For CPHA=0, the first bit must be on MOSI before the first clock edge
                        SPI_MOSI <= data_in[7];
                        // Move to the transfer state
                        state <= S_TRANSFER;
                    end
                end

                S_TRANSFER: begin
                    // Increment the clock divider counter on every system clock cycle
                    clk_div_cnt <= clk_div_cnt + 1;

                    // SPI Clock Generation (CPOL=0)
                    // Clock is low for the first half of the period, high for the second half.
                    if (clk_div_cnt < (CLK_DIVIDER / 2)) begin
                        SPI_CLK <= 1'b0;
                    end else begin
                        SPI_CLK <= 1'b1;
                    end

                    // CPHA=0: Data is sampled on the rising edge and changed on the falling edge.
                    // Rising edge occurs when clk_div_cnt transitions to CLK_DIVIDER/2.
                    // We check for the cycle just before this transition.
                    if (clk_div_cnt == (CLK_DIVIDER / 2) - 1) begin
                        // Sample the MISO line into the receive shift register
                        rx_reg <= {rx_reg[6:0], SPI_MISO};
                    end

                    // Falling edge occurs when clk_div_cnt wraps around from CLK_DIVIDER-1 to 0.
                    // We check for the last cycle of the period.
                    if (clk_div_cnt == CLK_DIVIDER - 1) begin
                        // Increment the bit counter after a full SPI clock cycle
                        bit_cnt <= bit_cnt + 1;

                        // Check if all 8 bits have been transferred
                        if (bit_cnt == 3'd7) begin
                            // If done, move to the cleanup state
                            state <= S_CLEANUP;
                        end else begin
                            // If not done, drive the next bit onto the MOSI line.
                            // The bit_cnt has not updated yet, so we use its current value
                            // to index the next bit.
                            SPI_MOSI <= tx_reg[6 - bit_cnt];
                        end
                        // Reset the clock divider for the next SPI clock cycle
                        clk_div_cnt <= 0;
                    end
                end

                S_CLEANUP: begin
                    // De-assert the slave enable to end the transaction
                    SPI_EN <= 1'b1;
                    // Ensure the clock returns to its idle state
                    SPI_CLK <= 1'b0;
                    // Latch the fully received data into the output register
                    data_out_reg <= rx_reg;
                    // Return to the idle state to wait for the next transaction
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // Assign the registered output to the final output port
    assign data_out = data_out_reg;

endmodule