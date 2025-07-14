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

    // Parameters
    // CLK_DIVIDER determines the SPI_CLK frequency relative to the system clk.
    // SPI_CLK period = 2 * CLK_DIVIDER * clk_period.
    // For example, if CLK_DIVIDER = 4, SPI_CLK period is 8 clk cycles.
    parameter CLK_DIVIDER = 4; 

    // State definitions for the FSM
    typedef enum logic [2:0] {
        IDLE,               // Waiting for a new transfer to start
        START_TRANSFER,     // Initialize transfer, assert SPI_EN, set first MOSI bit
        SHIFT_FALLING_EDGE, // Generate falling edge of SPI_CLK, MOSI is stable
        SHIFT_RISING_EDGE,  // Generate rising edge of SPI_CLK, sample MISO
        END_TRANSFER        // De-assert SPI_EN, return to idle state
    } spi_state_e;

    spi_state_e current_state, next_state;

    // Internal registers for data, bit count, and clock generation
    logic [7:0] data_in_reg;    // Latched input data to be transmitted
    logic [7:0] data_out_reg;   // Received data
    logic [2:0] bit_count;      // Counter for the 8 bits (0 to 7)
    logic [($clog2(CLK_DIVIDER)-1):0] clk_cnt; // Counter for generating SPI_CLK edges

    // Internal registers for SPI signals
    logic spi_clk_reg;  // Internal register for SPI_CLK (CPOL=1, CPHA=1)
    logic spi_en_reg;   // Internal register for SPI_EN (active low)
    logic spi_mosi_reg; // Internal register for SPI_MOSI

    // Assign internal registers to output ports
    assign SPI_CLK = spi_clk_reg;
    assign SPI_EN = spi_en_reg;
    assign SPI_MOSI = spi_mosi_reg;
    assign data_out = data_out_reg;

    // State and register updates on positive edge of clk or rst
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all registers to their idle/initial states
            current_state <= IDLE;
            data_in_reg <= 8'h00;
            data_out_reg <= 8'h00;
            bit_count <= 3'h0;
            clk_cnt <= '0;
            spi_clk_reg <= 1'b1; // CPOL=1: SPI_CLK idles high
            spi_en_reg <= 1'b1;  // SPI_EN is active low, so high when idle
            spi_mosi_reg <= 1'b0; // MOSI default low when idle
        end else begin
            current_state <= next_state; // Update current state
            
            // Update other registers based on the current state
            case (current_state)
                IDLE: begin
                    spi_en_reg <= 1'b1;  // Ensure SPI_EN is high (inactive)
                    spi_clk_reg <= 1'b1; // Ensure SPI_CLK is high (idle state for CPOL=1)
                    spi_mosi_reg <= 1'b0; // MOSI default low
                    data_out_reg <= 8'h00; // Clear received data
                    if (SPI_start) begin
                        data_in_reg <= data_in; // Latch data to be sent
                    end
                end
                START_TRANSFER: begin
                    spi_en_reg <= 1'b0; // Assert SPI_EN (active low)
                    spi_clk_reg <= 1'b1; // Keep clock high (CPOL=1)
                    bit_count <= 3'h0;   // Reset bit counter
                    clk_cnt <= '0;       // Reset clock divider counter
                    spi_mosi_reg <= data_in_reg[7]; // Drive MSB of data_in_reg onto MOSI
                end
                SHIFT_FALLING_EDGE: begin
                    if (clk_cnt == CLK_DIVIDER - 1) begin
                        spi_clk_reg <= 1'b0; // Generate falling edge of SPI_CLK
                        clk_cnt <= '0;       // Reset clock divider counter
                    end else begin
                        clk_cnt <= clk_cnt + 1; // Increment clock divider counter
                    end
                    // SPI_MOSI remains stable from previous state/edge
                end
                SHIFT_RISING_EDGE: begin
                    if (clk_cnt == CLK_DIVIDER - 1) begin
                        spi_clk_reg <= 1'b1; // Generate rising edge of SPI_CLK
                        // CPHA=1: Sample MISO on the rising edge (first edge of data valid)
                        data_out_reg <= {data_out_reg[6:0], SPI_MISO}; // Shift in MISO bit
                        bit_count <= bit_count + 1; // Increment bit counter
                        clk_cnt <= '0;              // Reset clock divider counter
                        
                        // Prepare the next MOSI bit if not all bits are sent
                        if (bit_count < 7) begin // Check if this was not the last bit (0-7)
                            spi_mosi_reg <= data_in_reg[7 - (bit_count + 1)]; // Drive next bit
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1; // Increment clock divider counter
                    end
                end
                END_TRANSFER: begin
                    spi_en_reg <= 1'b1;  // De-assert SPI_EN (inactive)
                    spi_clk_reg <= 1'b1; // Return SPI_CLK to idle high
                    spi_mosi_reg <= 1'b0; // MOSI default low
                end
            endcase
        end
    end

    // Next state logic (combinational)
    always_comb begin
        next_state = current_state; // Default to stay in current state
        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = START_TRANSFER; // Start transfer when SPI_start is high
                end
            end
            START_TRANSFER: begin
                next_state = SHIFT_FALLING_EDGE; // Immediately move to generate first falling edge
            end
            SHIFT_FALLING_EDGE: begin
                if (clk_cnt == CLK_DIVIDER - 1) begin
                    next_state = SHIFT_RISING_EDGE; // Move to generate rising edge after falling edge is complete
                end
            end
            SHIFT_RISING_EDGE: begin
                if (clk_cnt == CLK_DIVIDER - 1) begin
                    if (bit_count == 7) begin // All 8 bits (0 to 7) have been transferred
                        next_state = END_TRANSFER; // Move to end the transfer
                    end else begin
                        next_state = SHIFT_FALLING_EDGE; // Continue with next bit transfer
                    end
                end
            end
            END_TRANSFER: begin
                next_state = IDLE; // Return to idle state after transfer completion
            end
        endcase
    end

endmodule