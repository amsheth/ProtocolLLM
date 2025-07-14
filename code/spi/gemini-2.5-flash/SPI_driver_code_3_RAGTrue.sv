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
    localparam DATA_WIDTH = 8;          // Number of bits per transfer
    localparam SPI_CLK_DIVIDER = 4;     // Divides system clock to generate SPI_CLK. Must be >= 2 and even.
                                        // Example: SPI_CLK = clk / 4

    // FSM States
    typedef enum logic [2:0] {
        IDLE,
        START_TRANSFER,
        CLK_LOW_PHASE,  // SPI_CLK is low, preparing for rising edge
        CLK_HIGH_PHASE, // SPI_CLK is high, preparing for falling edge
        END_TRANSFER
    } spi_state_e;

    spi_state_e current_state, next_state;

    // Internal Registers
    logic [DATA_WIDTH-1:0] tx_data_reg;
    logic [DATA_WIDTH-1:0] rx_data_reg;
    logic [$clog2(DATA_WIDTH)-1:0] bit_counter; // Counts from 0 to DATA_WIDTH-1
    logic [$clog2(SPI_CLK_DIVIDER)-1:0] clk_div_counter; // Counter for SPI_CLK generation

    // Internal signals for outputs
    logic spi_clk_int;
    logic spi_en_int;
    logic spi_mosi_int;

    // Assign internal signals to module outputs
    assign SPI_CLK = spi_clk_int;
    assign SPI_EN = spi_en_int;
    assign SPI_MOSI = spi_mosi_int;
    assign data_out = rx_data_reg; // Output received data (may be partial during transfer)

    // FSM State and Output Logic (Synchronous with 'clk', Asynchronous 'rst')
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            spi_clk_int <= 1'b0; // CPOL=0, idle low
            spi_en_int <= 1'b1;  // Active low, so high when idle
            spi_mosi_int <= 1'b0;
            tx_data_reg <= '0;
            rx_data_reg <= '0;
            bit_counter <= '0;
            clk_div_counter <= '0;
        end else begin
            current_state <= next_state;

            // Default assignments to maintain values unless explicitly changed in a state
            spi_clk_int <= spi_clk_int;
            spi_en_int <= spi_en_int;
            spi_mosi_int <= spi_mosi_int;
            tx_data_reg <= tx_data_reg;
            rx_data_reg <= rx_data_reg;
            bit_counter <= bit_counter;
            clk_div_counter <= clk_div_counter;

            case (current_state)
                IDLE: begin
                    spi_clk_int <= 1'b0;
                    spi_en_int <= 1'b1;
                    spi_mosi_int <= 1'b0;
                    bit_counter <= '0;
                    clk_div_counter <= '0;
                    rx_data_reg <= '0; // Clear received data for new transfer
                end
                START_TRANSFER: begin
                    spi_en_int <= 1'b0; // Activate slave select
                    tx_data_reg <= data_in; // Load data to transmit
                    spi_mosi_int <= data_in[DATA_WIDTH-1]; // Place MSB on MOSI
                    spi_clk_int <= 1'b0; // Ensure clock is low
                    clk_div_counter <= '0; // Reset clock divider
                    bit_counter <= '0;
                end
                CLK_LOW_PHASE: begin
                    clk_div_counter <= clk_div_counter + 1;
                    spi_clk_int <= 1'b0; // Keep clock low
                end
                CLK_HIGH_PHASE: begin
                    clk_div_counter <= clk_div_counter + 1;
                    spi_clk_int <= 1'b1; // Keep clock high

                    // Sample MISO on the rising edge of SPI_CLK (CPHA=0)
                    // This occurs on the first 'clk' cycle of the CLK_HIGH_PHASE
                    if (clk_div_counter == (SPI_CLK_DIVIDER/2)) begin
                        rx_data_reg <= {rx_data_reg[DATA_WIDTH-2:0], SPI_MISO};
                    end

                    // Shift TX data and update MOSI on falling edge of SPI_CLK (CPHA=0)
                    // This occurs on the last 'clk' cycle of the CLK_HIGH_PHASE
                    if (clk_div_counter == (SPI_CLK_DIVIDER - 1)) begin
                        tx_data_reg <= tx_data_reg << 1; // Shift left for next bit
                        spi_mosi_int <= tx_data_reg[DATA_WIDTH-1]; // Next MSB
                        bit_counter <= bit_counter + 1;
                    end
                end
                END_TRANSFER: begin
                    spi_en_int <= 1'b1; // Deactivate slave select
                    spi_clk_int <= 1'b0; // Ensure clock is low
                    spi_mosi_int <= 1'b0; // MOSI to default low
                    bit_counter <= '0;
                    clk_div_counter <= '0;
                end
            endcase
        end
    end

    // FSM Next State Logic (Combinational)
    always_comb begin
        next_state = current_state; // Default to stay in current state
        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = START_TRANSFER;
                end
            end
            START_TRANSFER: begin
                next_state = CLK_LOW_PHASE; // Begin the first clock cycle
            end
            CLK_LOW_PHASE: begin
                // Transition to CLK_HIGH_PHASE after half of the SPI_CLK period
                if (clk_div_counter == (SPI_CLK_DIVIDER/2 - 1)) begin
                    next_state = CLK_HIGH_PHASE;
                end
            end
            CLK_HIGH_PHASE: begin
                // Transition to next state after a full SPI_CLK period
                if (clk_div_counter == (SPI_CLK_DIVIDER - 1)) begin
                    if (bit_counter == DATA_WIDTH - 1) begin
                        next_state = END_TRANSFER; // All bits transferred
                    end else begin
                        next_state = CLK_LOW_PHASE; // More bits to transfer
                    end
                end
            end
            END_TRANSFER: begin
                next_state = IDLE; // Always return to IDLE after transfer
            end
        endcase
    end

endmodule