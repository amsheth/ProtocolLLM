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
    // SPI_CLK frequency will be clk / (2 * CLK_DIV).
    // Example: If clk is 100MHz and CLK_DIV is 4, SPI_CLK is 12.5MHz.
    parameter CLK_DIV = 4;

    // Internal state machine definition
    typedef enum logic [2:0] {
        S_IDLE,
        S_PREPARE,
        S_TRANSFER_LEAD,  // Leading Edge phase: H->L, Sample MISO
        S_TRANSFER_TRAIL, // Trailing Edge phase: L->H, Change MOSI
        S_DONE
    } state_t;

    state_t state, next_state;

    // Internal registers for data handling and counters
    logic [7:0] tx_reg;
    logic [7:0] rx_reg;
    logic [2:0] bit_count;
    logic [$clog2(CLK_DIV)-1:0] clk_count;

    // State Register: Sequential logic for state transitions
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next State Logic: Combinational logic to determine the next state
    always_comb begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (SPI_start) begin
                    next_state = S_PREPARE;
                end
            end
            S_PREPARE: begin
                // This state ensures MOSI is set up before the first clock edge
                next_state = S_TRANSFER_LEAD;
            end
            S_TRANSFER_LEAD: begin
                // Wait for CLK_DIV cycles before moving
 to the trailing edge
                if (clk_count == CLK_DIV - 1) begin
                    next_state = S_TRANSFER_TRAIL;
                end
            end
            S_TRANSFER_TRAIL: begin
                // Wait for CLK_DIV cycles before moving to the next bit or finishing
                if (clk_count == CLK_DIV - 1) begin
                    if (bit_count == 3'd7) begin
                        next_state = S_DONE; // All 8 bits transferred
                    end else begin
                        next_state = S_TRANSFER_LEAD; // Go to next bit
                    end
                end
            end
            S_DONE: begin
                // Cleanup state, then return to idle
                next_state = S_IDLE;
            end
        endcase
    end

    // Output and Datapath Logic: Sequential logic for outputs and internal registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all outputs and internal registers to a known state
            SPI_EN      <= 1'b1;
            SPI_CLK     <= 1'b1; // CPOL=1: idle is high
            SPI_MOSI    <= 1'b0;
            data_out    <= '0;
            tx_reg      <= '0;
            rx_reg      <= '0;
            bit_count   <= '0;
            clk_count   <= '0;
        end else begin
            // Default action for the clock divider counter
            clk_count <= clk_count + 1;

            case (state)
                S_IDLE: begin
                    SPI_EN      <= 1'b1;
                    SPI_CLK     <= 1'b1; // Maintain idle high
                    bit_count   <= '0;
                    clk_count   <= '0;
                    data_out    <= rx_reg; // Make the last received data available

                    if (SPI_start) begin
                        // Latch the input data to be transmitted
                        tx_reg <= data_in;
                    end
                end

                S_PREPARE: begin
                    // Start the SPI transaction
                    SPI_EN <= 1'b0; // Assert chip enable
                    // CPHA=0: Data must be valid before the first clock edge.
                    // Set the first bit (MSB) on the MOSI line.
                    SPI_MOSI <= tx_reg[7];
                    clk_count <= '0; // Reset clock divider for the first phase
                end

                S_TRANSFER_LEAD: begin
                    // Leading Edge Phase (High -> Low)
                    SPI_CLK <= 1'b0;
                    // Sample MISO on the first cycle of this phase
                    if (clk_count == 0) begin
                        rx_reg <= {rx_reg[6:0], SPI_MISO};
                    end
                    // Reset clock divider when phase is complete
                    if (clk_count == CLK_DIV - 1) begin
                        clk_count <= '0;
                    end
                end

                S_TRANSFER_TRAIL: begin
                    // Trailing Edge Phase (Low -> High)
                    SPI_CLK <= 1'b1;
                    // Change MOSI on the first cycle of this phase
                    if (clk_count == 0) begin
                        // Shift transmit register to get the next bit
                        tx_reg <= tx_reg << 1;
                        // The new bit to send is what was at index 6 before the shift
                        SPI_MOSI <= tx_reg[6];
                    end
                    // When phase is complete, increment bit counter and reset clock divider
                    if (clk_count == CLK_DIV - 1) begin
                        bit_count <= bit_count + 1;
                        clk_count <= '0;
                    end
                end

                S_DONE: begin
                    // End the transaction
                    SPI_EN <= 1'b1; // De-assert chip enable
                    SPI_CLK <= 1'b1; // Return clock to idle state
                    // The last bit was sampled in the final S_TRANSFER_LEAD state.
                    // rx_reg is now complete and will be assigned to data_out in S_IDLE.
                end
            endcase
        end
    end

endmodule