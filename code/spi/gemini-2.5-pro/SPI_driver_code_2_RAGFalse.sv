module SPI_driver (
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

    // SPI parameters for Master Mode
    // CPOL = 0: Clock is idle low
    // CPHA = 1: Data is sampled on the trailing (falling) edge
    //           Data is changed on the leading (rising) edge
    localparam CPOL = 0;
    localparam CPHA = 1;

    // State machine definition
    typedef enum logic [1:0] {
        S_IDLE,
        S_TRANSFER,
        S_DONE
    } state_t;

    state_t state, next_state;

    // Internal registers
    logic [7:0] tx_reg;      // Transmit shift register
    logic [7:0] rx_reg;      // Receive shift register
    logic [3:0] bit_count;   // Counts bits transferred (0 to 8)

    // State register - clocked process
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next state logic - combinational process
    always_comb begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (SPI_start) begin
                    next_state = S_TRANSFER;
                end
            end
            S_TRANSFER: begin
                // A full SPI clock cycle takes 2 system clock cycles.
                // We transition out after 8 full SPI cycles (16 system clock cycles).
                // We use a bit counter that increments on the falling edge of SPI_CLK.
                if (bit_count == 8) begin
                    next_state = S_DONE;
                end
            end
            S_DONE: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // Main sequential logic for data path and outputs
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_EN <= 1'b1;
            SPI_CLK <= CPOL;
            SPI_MOSI <= 1'b0;
            data_out <= 8'h00;
            tx_reg <= 8'h00;
            rx_reg <= 8'h00;
            bit_count <= 4'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    SPI_EN <= 1'b1;      // De-assert slave select
                    SPI_CLK <= CPOL;     // Clock is idle
                    bit_count <= 4'd0;
                    if (SPI_start) begin
                        SPI_EN <= 1'b0;      // Assert slave select
                        tx_reg <= data_in;   // Load data to transmit
                        SPI_MOSI <= data_in[7]; // Pre-load MSB for the first clock edge
                    end
                end

                S_TRANSFER: begin
                    // Generate SPI clock at half the system clock frequency
                    SPI_CLK <= ~SPI_CLK;

                    // CPHA=1: Change on leading edge, sample on trailing edge
                    // For CPOL=0, leading is rising, trailing is falling.
                    // The SPI_CLK value has just been updated for the *current* cycle.
                    // When SPI_CLK is 1, it's a rising edge. When it's 0, it's a falling edge.

                    if (SPI_CLK == 1'b1) begin // Just rose from 0 to 1
                        // Change data on MOSI
                        // The bit to be transmitted was already set on the previous state change
                        // or the previous falling edge. Now we shift the register to prepare the next bit.
                        if (bit_count < 7) begin
                           SPI_MOSI <= tx_reg[6 - bit_count];
                        end
                    end else begin // Just fell from 1 to 0
                        // Sample data from MISO
                        rx_reg <= {rx_reg[6:0], SPI_MISO};
                        bit_count <= bit_count + 1;
                    end
                end

                S_DONE: begin
                    SPI_EN <= 1'b1;      // De-assert slave select
                    SPI_CLK <= CPOL;     // Return clock to idle state
                    data_out <= rx_reg;  // Output the received data
                    bit_count <= 4'd0;   // Reset bit counter for next transaction
                end
            endcase
        end
    end

endmodule