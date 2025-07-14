module SPI_driver #(
    parameter CLK_DIV_FACTOR = 2 // SPI_CLK_freq = clk_freq / (2 * CLK_DIV_FACTOR)
                                 // For example, if CLK_DIV_FACTOR = 2, SPI_CLK is clk / 4
) (
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

    // Internal signals
    logic [7:0] s_data_in_reg;
    logic [7:0] s_data_out_reg;
    logic [3:0] bit_count; // Counts from 0 to 7 for 8 bits
    logic [7:0] clk_div_counter; // Counter for SPI_CLK generation
    logic s_spi_clk;
    logic s_spi_en;
    logic s_spi_mosi;

    // State machine definition
    typedef enum logic [1:0] {
        IDLE,
        TRANSFER,
        END_TRANSFER
    } spi_state_e;

    spi_state_e current_state, next_state;

    // State register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic
    always_comb begin
        next_state = current_state; // Default to staying in current state
        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = TRANSFER;
                end
            end
            TRANSFER: begin
                // Transition to END_TRANSFER after all 8 bits (0-7) have been processed
                if (bit_count == 8) begin
                    next_state = END_TRANSFER;
                end
            end
            END_TRANSFER: begin
                // After completing transfer, return to IDLE
                next_state = IDLE;
            end
            default: next_state = IDLE; // Should not happen
        endcase
    end

    // Output assignments
    assign SPI_MOSI = s_spi_mosi;
    assign SPI_CLK = s_spi_clk;
    assign SPI_EN = s_spi_en;
    assign data_out = s_data_out_reg;

    // Main FSM logic and data path
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s_spi_en <= 1'b1; // SPI_EN is active low, so high when idle
            s_spi_clk <= 1'b0; // CPOL=0, SPI_CLK is low when idle
            s_spi_mosi <= 1'b0;
            s_data_in_reg <= 8'h00;
            s_data_out_reg <= 8'h00;
            bit_count <= 4'h0;
            clk_div_counter <= 8'h00;
        end else begin
            // Default assignments to hold values
            s_spi_en <= 1'b1; // Default to inactive
            s_spi_clk <= s_spi_clk;
            s_spi_mosi <= s_spi_mosi;
            s_data_out_reg <= s_data_out_reg;
            s_data_in_reg <= s_data_in_reg;
            bit_count <= bit_count;
            clk_div_counter <= clk_div_counter;

            case (current_state)
                IDLE: begin
                    s_spi_en <= 1'b1; // Ensure SPI_EN is high
                    s_spi_clk <= 1'b0; // Ensure SPI_CLK is low
                    s_spi_mosi <= 1'b0;
                    s_data_out_reg <= 8'h00; // Clear output data
                    bit_count <= 4'h0; // Reset bit counter
                    clk_div_counter <= 8'h00; // Reset clock divider

                    if (SPI_start) begin
                        s_data_in_reg <= data_in; // Load data to be sent
                        s_spi_en <= 1'b0; // Assert SPI_EN (active low)
                    end
                end
                TRANSFER: begin
                    s_spi_en <= 1'b0; // Keep SPI_EN asserted

                    // SPI_CLK generation
                    if (clk_div_counter == (CLK_DIV_FACTOR - 1)) begin
                        clk_div_counter <= 8'h00;
                        s_spi_clk <= ~s_spi_clk; // Toggle SPI_CLK
                    end else begin
                        clk_div_counter <= clk_div_counter + 1;
                    end

                    // Data transfer logic for CPOL=0, CPHA=1
                    // MOSI changes on the rising edge of SPI_CLK
                    // MISO samples on the falling edge of SPI_CLK

                    // Check for rising edge of SPI_CLK (s_spi_clk is currently 0, and about to toggle to 1)
                    if (s_spi_clk == 1'b0 && clk_div_counter == (CLK_DIV_FACTOR - 1)) begin
                        // Drive MOSI with the current bit (MSB first)
                        s_spi_mosi <= s_data_in_reg[7 - bit_count];
                    end
                    // Check for falling edge of SPI_CLK (s_spi_clk is currently 1, and about to toggle to 0)
                    else if (s_spi_clk == 1'b1 && clk_div_counter == (CLK_DIV_FACTOR - 1)) begin
                        // Sample MISO and store it
                        s_data_out_reg[7 - bit_count] <= SPI_MISO;
                        // Increment bit_count after sampling each bit
                        bit_count <= bit_count + 1;
                    end
                end
                END_TRANSFER: begin
                    s_spi_en <= 1'b1; // Deassert SPI_EN
                    s_spi_clk <= 1'b0; // Ensure clock returns to idle low
                    s_spi_mosi <= 1'b0; // Ensure MOSI is low
                    bit_count <= 4'h0; // Reset bit counter
                    clk_div_counter <= 8'h00; // Reset clock divider
                end
            endcase
        end
    end

endmodule