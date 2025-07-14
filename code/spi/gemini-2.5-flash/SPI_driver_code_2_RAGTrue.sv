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

    // Parameters for configuration
    localparam DATA_WIDTH = 8; // Number of bits per transfer (e.g., 8 for byte transfer)
    // CLK_DIV_FACTOR determines the SPI clock frequency relative to the system clock.
    // A value of N means SPI_CLK toggles every N system clock cycles.
    // One full SPI clock period is 2 * N system clock cycles.
    localparam CLK_DIV_FACTOR = 4; // Example: 8 system clock cycles per SPI bit period.

    // State definitions for the FSM
    typedef enum logic [1:0] {
        IDLE,           // Waiting for a transfer to start
        START_TRANSFER, // Initialize registers and assert SPI_EN
        SHIFTING,       // Perform data transfer (clock generation, data shifting)
        END_TRANSFER    // De-assert SPI_EN and finalize transfer
    } spi_state_e;

    // Internal registers for FSM and data path
    spi_state_e current_state, next_state;
    logic [DATA_WIDTH-1:0] tx_data_reg; // Register to hold data to be transmitted
    logic [DATA_WIDTH-1:0] rx_data_reg; // Register to accumulate received data
    logic [$clog2(DATA_WIDTH)-1:0] bit_counter; // Counts bits transferred (e.g., 7 down to 0 for 8 bits)
    logic [$clog2(2 * CLK_DIV_FACTOR)-1:0] clk_div_counter; // Counter for SPI clock generation

    // Internal registers for SPI output signals
    logic spi_clk_reg;  // Internal register for SPI_CLK
    logic spi_mosi_reg; // Internal register for SPI_MOSI
    logic spi_en_reg;   // Internal register for SPI_EN (Slave Select, active low)

    // Assign internal registers to module outputs
    assign SPI_MOSI = spi_mosi_reg;
    assign SPI_CLK = spi_clk_reg;
    assign SPI_EN = spi_en_reg;
    assign data_out = rx_data_reg; // Received data is valid when transfer completes

    // State register and synchronous reset logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            tx_data_reg <= '0;
            rx_data_reg <= '0;
            bit_counter <= '0;
            clk_div_counter <= '0;
            spi_clk_reg <= 1'b0;  // CPOL=0: Clock idle low
            spi_mosi_reg <= 1'b0; // MOSI idle low
            spi_en_reg <= 1'b1;   // SPI_EN idle high (inactive)
        end else begin
            current_state <= next_state; // Update current state
            // Update other registers based on the current state and transitions
            case (current_state)
                IDLE: begin
                    // Ensure idle states are maintained
                    spi_en_reg <= 1'b1;
                    spi_clk_reg <= 1'b0;
                    clk_div_counter <= '0; // Reset clock divider counter
                end
                START_TRANSFER: begin
                    tx_data_reg <= data_in;
                    rx_data_reg <= '0; // Clear receive buffer for new data
                    bit_counter <= DATA_WIDTH - 1; // Start with MSB (e.g., bit 7 for 8 bits)
                    spi_en_reg <= 1'b0; // Activate slave select (active low)
                    spi_clk_reg <= 1'b0; // Clock starts low (CPOL=0)
                    spi_mosi_reg <= data_in[DATA_WIDTH - 1]; // Put MSB of data_in on MOSI
                    clk_div_counter <= '0; // Reset clock divider counter
                end
                SHIFTING: begin
                    // Increment clock divider counter
                    clk_div_counter <= clk_div_counter + 1;

                    // Clock generation and data shifting logic for CPOL=0, CPHA=1
                    if (clk_div_counter == CLK_DIV_FACTOR - 1) begin
                        // This is the point where SPI_CLK transitions from low to high (first edge for CPHA=1)
                        spi_clk_reg <= 1'b1;
                        // The spi_mosi_reg bit is stable and driven here.
                    end else if (clk_div_counter == (2 * CLK_DIV_FACTOR) - 1) begin
                        // This is the point where SPI_CLK transitions from high to low (second edge for CPHA=1)
                        spi_clk_reg <= 1'b0;

                        // Sample MISO on the falling edge (CPHA=1)
                        // For MSB first reception, shift rx_data_reg left and append the new bit
                        rx_data_reg <= {rx_data_reg[DATA_WIDTH-2:0], SPI_MISO};

                        // Decrement bit counter
                        bit_counter <= bit_counter - 1;

                        // Prepare the next MOSI bit for the next SPI clock cycle
                        // This bit will be stable during the low phase of SPI_CLK
                        if (bit_counter != 0) begin // If not the last bit
                            spi_mosi_reg <= tx_data_reg[bit_counter - 1];
                        end else begin
                            // After the last bit, MOSI can be driven low or high-Z. Driving low is safer.
                            spi_mosi_reg <= 1'b0;
                        end
                    end
                end
                END_TRANSFER: begin
                    spi_en_reg <= 1'b1; // Deactivate slave select
                    spi_clk_reg <= 1'b0; // Ensure clock is low
                    clk_div_counter <= '0; // Reset clock divider counter
                end
            endcase
        end
    end

    // Next state logic (combinational)
    always_comb begin
        next_state = current_state; // Default: stay in current state

        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = START_TRANSFER;
                end
            end
            START_TRANSFER: begin
                next_state = SHIFTING;
            end
            SHIFTING: begin
                // Transition to END_TRANSFER after the last bit's full SPI clock cycle is complete
                if (clk_div_counter == (2 * CLK_DIV_FACTOR) - 1) begin
                    if (bit_counter == 0) begin // All bits have been processed
                        next_state = END_TRANSFER;
                    end
                end
            end
            END_TRANSFER: begin
                next_state = IDLE; // Return to idle to await next transfer
            end
        endcase
    end

endmodule