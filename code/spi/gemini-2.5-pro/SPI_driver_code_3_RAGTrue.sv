/**
 * @module SPI_driver
 * @brief A simple SPI Master Driver.
 *
 * @param CLK_DIVIDER Sets the SPI clock speed.
 *        SPI_CLK frequency = clk / (2 * CLK_DIVIDER).
 *        For a 50MHz system clk and CLK_DIVIDER=4, SPI_CLK is 6.25MHz.
 *
 * This module implements an SPI master for a single slave device.
 * It operates in SPI Mode 0 (CPOL=0, CPHA=0).
 * A transaction is initiated by a single-cycle pulse on SPI_start.
 */
module SPI_driver #(
    parameter CLK_DIVIDER = 4
) (
    input  logic        clk,         // System clock
    input  logic        rst,         // System reset (active high)
    input  logic [7:0]  data_in,     // Data to be transmitted
    input  logic        SPI_MISO,    // Master In, Slave Out data line
    input  logic        SPI_start,   // Start signal for the SPI transaction
    output logic        SPI_MOSI,    // Master Out, Slave In data line
    output logic        SPI_CLK,     // SPI clock signal
    output logic        SPI_EN,      // SPI enable/slave select (active low)
    output logic [7:0]  data_out     // Data received from the slave
);

    // State machine definition
    typedef enum logic [1:0] {
        S_IDLE,
        S_TRANSFER,
        S_END
    } state_t;

    // Internal signals and registers
    state_t state, next_state;
    logic [7:0] tx_reg;      // Transmit data shift register
    logic [7:0] rx_reg;      // Receive data shift register
    logic [$clog2(CLK_DIVIDER*2)-1:0] clk_count; // Counter for SPI clock generation
    logic [3:0] bit_count;   // Counts the number of bits transferred (0-8)

    // Sequential logic for state transitions and register updates
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            tx_reg    <= 8'h00;
            rx_reg    <= 8'h00;
            clk_count <= 0;
            bit_count <= 0;
        end else begin
            state <= next_state;

            // Update registers based on the current state
            case (state)
                S_IDLE: begin
                    if (SPI_start) begin
                        tx_reg <= data_in; // Load data on start
                    end
                end

                S_TRANSFER: begin
                    // Clock divider logic
                    if (clk_count == (CLK_DIVIDER * 2) - 1) begin
                        clk_count <= 0;
                    end else begin
                        clk_count <= clk_count + 1;
                    end

                    // CPHA=0: Sample MISO on the RISING edge of SPI_CLK
                    if (clk_count == CLK_DIVIDER - 1) begin
                        rx_reg <= {rx_reg[6:0], SPI_MISO};
                    end
                    // CPHA=0: Data is shifted internally on the FALLING edge of SPI_CLK
                    else if (clk_count == (CLK_DIVIDER * 2) - 1) begin
                        tx_reg <= {tx_reg[6:0], 1'b0}; // Shift left for next bit
                        bit_count <= bit_count + 1;
                    end
                end

                S_END: begin
                    // Reset counters for the next transfer
                    bit_count <= 0;
                    clk_count <= 0;
                end
            endcase
        end
    end

    // Combinational logic for state transitions and output signals
    always_comb begin
        // Default assignments
        next_state = state;
        SPI_EN     = 1'b1;         // Default to disabled
        SPI_CLK    = 1'b0;         // CPOL=0: Idle clock is low
        SPI_MOSI   = tx_reg[7];    // Transmit MSB first
        data_out   = rx_reg;       // Assign received data to output

        case (state)
            S_IDLE: begin
                SPI_EN = 1'b1;
                if (SPI_start) begin
                    next_state = S_TRANSFER;
                end
            end

            S_TRANSFER: begin
                SPI_EN = 1'b0; // Assert slave enable

                // Generate SPI_CLK based on the divider counter
                if (clk_count < CLK_DIVIDER) begin
                    SPI_CLK = 1'b0; // First half of the period is low
                end else begin
                    SPI_CLK = 1'b1; // Second half is high
                end

                // CPHA=0: MOSI data is changed on the falling edge.
                // This is achieved by shifting tx_reg on the falling edge (in the always_ff block)
                // and combinationally assigning SPI_MOSI from its MSB. The data is stable
                // for the entire low phase and the subsequent rising edge.

                // Check if 8 bits have been transferred
                if (bit_count == 8) begin
                    next_state = S_END;
                end
            end

            S_END: begin
                // This state lasts for one system clock cycle to de-assert SPI_EN
                SPI_EN   = 1'b1;
                data_out = rx_reg; // Ensure final data is output
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

endmodule