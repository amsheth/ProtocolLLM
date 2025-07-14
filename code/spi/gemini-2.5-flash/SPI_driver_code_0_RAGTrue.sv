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
    localparam int BITS_PER_TRANSFER = 8; // Fixed to 8 bits for this driver
    localparam int CLK_DIV_FACTOR = 4;    // SPI_CLK frequency = clk_freq / CLK_DIV_FACTOR
                                          // This means SPI_CLK period is 4 * clk periods.
                                          // Half period is 2 * clk periods.

    // State machine definition
    typedef enum logic [2:0] {
        IDLE,
        START_TRANSFER,
        CLK_HIGH_PRE_FALL, // Clock is high, preparing for falling edge (MOSI stable)
        CLK_LOW_POST_FALL, // Clock is low, preparing for rising edge (MISO stable)
        END_TRANSFER
    } spi_state_t;

    spi_state_t current_state, next_state;

    // Internal registers
    logic [BITS_PER_TRANSFER-1:0] tx_data_reg; // Data to be transmitted
    logic [BITS_PER_TRANSFER-1:0] rx_data_reg; // Data received
    logic [clog2(BITS_PER_TRANSFER)-1:0] bit_idx; // Current bit index (0 to BITS_PER_TRANSFER-1)
    logic [clog2(CLK_DIV_FACTOR)-1:0] clk_div_cnt; // Clock divider counter

    logic spi_clk_reg;  // Internal SPI_CLK state
    logic spi_mosi_reg; // Internal SPI_MOSI state
    logic spi_en_reg;   // Internal SPI_EN state

    // Synchronizer for SPI_start input and rising edge detection
    logic spi_start_q1, spi_start_q2;
    logic spi_start_prev; // Previous state of synchronized SPI_start
    logic spi_start_rise; // Rising edge detected

    // Output assignments
    assign SPI_MOSI = spi_mosi_reg;
    assign SPI_CLK  = spi_clk_reg;
    assign SPI_EN   = spi_en_reg;
    assign data_out = rx_data_reg; // Output received data

    // Sequential logic for state, registers, and clock generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state  <= IDLE;
            spi_clk_reg    <= 1'b1; // CPOL=1, idle high
            spi_en_reg     <= 1'b1; // Inactive
            spi_mosi_reg   <= 1'b0;
            tx_data_reg    <= '0;
            rx_data_reg    <= '0;
            bit_idx        <= '0;
            clk_div_cnt    <= '0;
            spi_start_q1   <= 1'b0; // Initialize synchronizer flops
            spi_start_q2   <= 1'b0;
            spi_start_prev <= 1'b0; // Initialize edge detector flop
        end else begin
            // Synchronizer for SPI_start
            spi_start_q1 <= SPI_start;
            spi_start_q2 <= spi_start_q1;
            // Store previous synchronized value for edge detection
            spi_start_prev <= spi_start_q2;

            current_state <= next_state; // Update current state

            // Clock divider logic: increments unless reset or in IDLE
            if (next_state == START_TRANSFER) begin // Reset counter when starting a new transfer
                clk_div_cnt <= '0;
            end else if (current_state != IDLE) begin // Only run clock divider when not idle
                if (clk_div_cnt == CLK_DIV_FACTOR - 1) begin
                    clk_div_cnt <= '0;
                end else begin
                    clk_div_cnt <= clk_div_cnt + 1;
                end
            end else begin
                clk_div_cnt <= '0; // Keep reset in IDLE
            end

            // SPI_CLK generation based on CPOL=1 and clock divider
            case (current_state)
                IDLE: begin
                    spi_clk_reg <= 1'b1; // Keep high in idle (CPOL=1)
                end
                CLK_HIGH_PRE_FALL: begin
                    // Toggle CLK to low after half period (falling edge)
                    if (clk_div_cnt == CLK_DIV_FACTOR/2 - 1) begin
                        spi_clk_reg <= 1'b0;
                    end
                end
                CLK_LOW_POST_FALL: begin
                    // Toggle CLK to high after full period (rising edge)
                    if (clk_div_cnt == CLK_DIV_FACTOR - 1) begin
                        spi_clk_reg <= 1'b1;
                    end
                end
                default: begin
                    // For START_TRANSFER and END_TRANSFER, CLK should be high
                    spi_clk_reg <= 1'b1;
                end
            endcase

            // Data and control signal updates based on state
            case (current_state)
                IDLE: begin
                    spi_en_reg   <= 1'b1; // Slave Select inactive
                    spi_mosi_reg <= 1'b0; // MOSI low in idle
                    rx_data_reg  <= '0;   // Clear received data
                    bit_idx      <= '0;
                end
                START_TRANSFER: begin
                    spi_en_reg   <= 1'b0; // Slave Select active
                    tx_data_reg  <= data_in; // Load data to transmit
                    bit_idx      <= '0;
                    // Set MOSI for the first bit (MSB) before the first falling edge
                    spi_mosi_reg <= data_in[BITS_PER_TRANSFER - 1];
                end
                CLK_HIGH_PRE_FALL: begin
                    // MOSI is stable before the falling edge (CPHA=1)
                    // It was set in START_TRANSFER or at the end of CLK_LOW_POST_FALL
                    spi_mosi_reg <= tx_data_reg[BITS_PER_TRANSFER - 1 - bit_idx];
                end
                CLK_LOW_POST_FALL: begin
                    // Sample MISO on the rising edge (CPHA=1)
                    if (clk_div_cnt == CLK_DIV_FACTOR - 1) begin
                        rx_data_reg[BITS_PER_TRANSFER - 1 - bit_idx] <= SPI_MISO;
                        bit_idx <= bit_idx + 1; // Move to next bit
                    end
                end
                END_TRANSFER: begin
                    spi_en_reg <= 1'b1; // Slave Select inactive
                end
            endcase
        end
    end

    // Combinational logic for next state determination
    assign spi_start_rise = spi_start_q2 && !spi_start_prev; // Detect rising edge of synchronized SPI_start

    always_comb begin
        next_state = current_state; // Default: stay in current state

        case (current_state)
            IDLE: begin
                if (spi_start_rise) begin // Start transfer on rising edge of SPI_start
                    next_state = START_TRANSFER;
                end
            end
            START_TRANSFER: begin
                // Immediately transition to the first clock phase after setup
                next_state = CLK_HIGH_PRE_FALL;
            end
            CLK_HIGH_PRE_FALL: begin
                // Transition to CLK_LOW_POST_FALL after half clock period (falling edge)
                if (clk_div_cnt == CLK_DIV_FACTOR/2 - 1) begin
                    next_state = CLK_LOW_POST_FALL;
                end
            end
            CLK_LOW_POST_FALL: begin
                // Transition after full clock period (rising edge)
                if (clk_div_cnt == CLK_DIV_FACTOR - 1) begin
                    if (bit_idx == BITS_PER_TRANSFER - 1) begin // All bits transferred
                        next_state = END_TRANSFER;
                    end else begin
                        next_state = CLK_HIGH_PRE_FALL; // More bits to transfer
                    end
                end
            end
            END_TRANSFER: begin
                // After completing transfer, return to IDLE
                next_state = IDLE;
            end
            default: next_state = IDLE; // Should not be reached
        endcase
    end

endmodule