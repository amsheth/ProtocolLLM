module SPI_driver(
    input logic clk,
    input logic rst,
    input logic [7:0] data_in,
    input logic SPI_MISO,
    input logic SPI_start, // Active high pulse to start transfer
    output logic SPI_MOSI,
    output logic SPI_CLK,
    output logic SPI_EN, // Active low slave select
    output logic [7:0] data_out
);

    // Internal state definition for the FSM
    typedef enum logic [2:0] {
        IDLE,
        SETUP_TRANSFER,
        FALLING_EDGE_CLK, // Clock goes low, sample MISO
        RISING_EDGE_CLK,  // Clock goes high, change MOSI
        END_TRANSFER
    } spi_state_t;

    spi_state_t current_state, next_state;

    // Internal registers for outputs to avoid combinational loops and for sequential logic
    logic spi_mosi_reg;
    logic spi_clk_reg;
    logic spi_en_reg;
    logic [7:0] data_out_reg;

    // Data buffers for transmit and receive
    logic [7:0] tx_buffer;
    logic [7:0] rx_buffer;
    logic [3:0] bit_count; // Counter for 8 bits (0 to 7)

    // Signal for detecting the rising edge of SPI_start
    logic spi_start_prev;

    // Assign outputs from internal registers
    assign SPI_MOSI = spi_mosi_reg;
    assign SPI_CLK  = spi_clk_reg;
    assign SPI_EN   = spi_en_reg;
    assign data_out = data_out_reg;

    // State register and edge detection for SPI_start
    always_ff @(posedge clk or pos
edge rst) begin
        if (rst) begin
            current_state <= IDLE;
            spi_start_prev <= 1'b0; // Initialize previous state of SPI_start
        end else begin
            current_state <= next_state;
            spi_start_prev <= SPI_start; // Update previous state for edge detection
        end
    end

    // Next state logic and output logic (combinational)
    always_comb begin
        // Default assignments to retain current values and avoid latches
        next_state     = current_state;
        spi_mosi_reg   = spi_mosi_reg;
        spi_clk_reg    = spi_clk_reg;
        spi_en_reg     = spi_en_reg;
        data_out_reg   = data_out_reg;

        case (current_state)
            IDLE: begin
                spi_clk_reg  = 1'b1; // CPOL=1: Clock idle high
                spi_en_reg   = 1'b1; // Slave select inactive (high)
                spi_mosi_reg = 1'b0; // MOSI low when idle
                data_out_reg = 8'b0; // Clear output data

                // Start transfer on the rising edge of SPI_start
                if (SPI_start && !spi_start_prev) begin
                    next_state = SETUP_TRANSFER;
                end
            end

            SETUP_TRANSFER: begin
                tx_buffer    = data_in;    // Load data to transmit
                rx_buffer    = 8'b0;       // Clear receive buffer
                bit_count    = 4'd0;       // Reset bit counter
                spi_en_reg   = 1'b0;       // Activate slave select (active low)
                spi_clk_reg  = 1'b1;       // Clock remains high (CPOL=1)
                spi_mosi_reg = tx_buffer[7]; // MSB first: put the most significant bit on MOSI
                next_state   = FALLING_EDGE_CLK; // Ready for the first clock edge
            end

            FALLING_EDGE_CLK: begin
                // CPOL=1, CPHA=0: Data sampled on falling edge
                spi_clk_reg = 1'b0; // Clock goes low
                // Sample MISO: For MSB first, the received bit is shifted into the MSB position of rx_buffer
                rx_buffer = {SPI_MISO, rx_buffer[7:1]}; 
                next_state  = RISING_EDGE_CLK;
            end

            RISING_EDGE_CLK: begin
                // CPOL=1, CPHA=0: Data changed on rising edge
                spi_clk_reg = 1'b1; // Clock goes high
                tx_buffer   = tx_buffer << 1; // Shift TX data left to bring next bit to MSB position
                bit_count   = bit_count + 1;

                if (bit_count < 8) begin // Check if all 8 bits have been processed
                    spi_mosi_reg = tx_buffer[7]; // Put the next MSB on MOSI
                    next_state   = FALLING_EDGE_CLK;
                end else begin
                    next_state   = END_TRANSFER; // All bits transferred, go to end state
                end
            end

            END_TRANSFER: begin
                spi_en_reg   = 1'b1;       // Deactivate slave select
                spi_clk_reg  = 1'b1;       // Clock returns to idle high
                spi_mosi_reg = 1'b0;       // MOSI low when idle
                data_out_reg = rx_buffer;  // Output the received data
                next_state   = IDLE;       // Return to idle state
            end

            default: begin
                next_state = IDLE; // Should not be reached, but good for robustness
            end
        endcase
    end

endmodule