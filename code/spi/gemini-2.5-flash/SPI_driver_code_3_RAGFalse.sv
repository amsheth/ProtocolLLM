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

    // Internal registers for outputs and data
    logic [7:0] s_data_in_reg;  // Shift register for data to transmit
    logic [7:0] s_data_out_reg; // Shift register for received data
    logic [2:0] bit_count;      // Counter for 8 bits (0 to 7)
    logic spi_clk_reg;          // Internal register for SPI_CLK
    logic spi_mosi_reg;         // Internal register for SPI_MOSI
    logic spi_en_reg;           // Internal register for SPI_EN (Chip Select)

    // State machine definition
    typedef enum logic [1:0] {
        IDLE,       // Waiting for a transaction to start
        START_TX,   // Initialize transaction, assert CS
        TX_RX_BITS, // Transmit/Receive 8 bits
        END_TX      // End transaction, de-assert CS
    } spi_state_e;

    spi_state_e current_state, next_state;

    // FSM State Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // FSM Next State Logic
    always_comb begin
        next_state = current_state; // Default to stay in current state
        case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = START_TX;
                end
            end
            START_TX: begin
                next_state = TX_RX_BITS;
            end
            TX_RX_BITS: begin
                // After 8 bits are fully processed (bit_count goes from 0 to 7, then increments to 8)
                if (bit_count == 3'd8) begin
                    next_state = END_TX;
                end
            end
            END_TX: begin
                next_state = IDLE;
            end
        endcase
    end

    // Output Logic and Data Path
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_en_reg     <= 1'b1;   // SPI_EN inactive (high)
            spi_clk_reg    <= 1'b0;   // CPOL=0, idle low
            spi_mosi_reg   <= 1'b0;
            s_data_in_reg  <= 8'h00;
            s_data_out_reg <= 8'h00;
            bit_count      <= 3'd0;
        end else begin
            case (current_state)
                IDLE: begin
                    spi_en_reg     <= 1'b1;   // Keep inactive
                    spi_clk_reg    <= 1'b0;   // Keep idle low
                    spi_mosi_reg   <= 1'b0;   // Keep low
                    s_data_out_reg <= 8'h00;   // Clear received data
                    bit_count      <= 3'd0;   // Reset bit counter
                    if (SPI_start) begin
                        s_data_in_reg <= data_in; // Load data to transmit
                    end
                end
                START_TX: begin
                    spi_en_reg     <= 1'b0;   // Assert SPI_EN (active low)
                    spi_clk_reg    <= 1'b0;   // Ensure SPI_CLK is low before first edge
                    spi_mosi_reg   <= s_data_in_reg[7]; // Set MSB of data_in on MOSI
                    bit_count      <= 3'd0;   // Reset bit counter
                end
                TX_RX_BITS: begin
                    // CPOL=0, CPHA=0:
                    // SPI_CLK is low when idle.
                    // Data is sampled on the rising edge of SPI_CLK.
                    // Data is changed on the falling edge of SPI_CLK.
                    // This implementation assumes SPI_CLK runs at clk/2.

                    if (spi_clk_reg == 1'b0) begin // Current SPI_CLK is low, about to go high
                        spi_clk_reg <= 1'b1; // Drive SPI_CLK high (rising edge)
                        // On the rising edge, sample MISO
                        s_data_out_reg <= {s_data_out_reg[6:0], SPI_MISO};
                    end else begin // Current SPI_CLK is high, about to go low
                        spi_clk_reg <= 1'b0; // Drive SPI_CLK low (falling edge)
                        // On the falling edge, change MOSI for the next bit
                        s_data_in_reg <= s_data_in_reg << 1; // Shift out current bit
                        spi_mosi_reg <= s_data_in_reg[6]; // Set next bit (MSB of shifted data)
                        bit_count <= bit_count + 1; // Increment bit counter after a full SPI clock cycle
                    end
                end
                END_TX: begin
                    spi_en_reg     <= 1'b1;   // De-assert SPI_EN
                    spi_clk_reg    <= 1'b0;   // Return SPI_CLK to idle low
                    spi_mosi_reg   <= 1'b0;   // Return MOSI to idle low
                    // data_out is assigned s_data_out_reg outside this always block
                end
            endcase
        end
    end

    // Assign outputs from internal registers
    assign SPI_MOSI = spi_mosi_reg;
    assign SPI_CLK  = spi_clk_reg;
    assign SPI_EN   = spi_en_reg;
    assign data_out = s_data_out_reg; // Output the received data when transaction completes

endmodule