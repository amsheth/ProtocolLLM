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

    // State machine states
    typedef enum { IDLE, SHIFT, DONE } state_t;
    state_t current_state;

    // Internal signals
    logic [7:0] tx_data;   // Data to transmit
    logic [7:0] rx_data;   // Data received
    logic [3:0] bit_count; // Number of bits processed
    logic clock_high;      // Current state of SPI_CLK

    // Reset values
    initial begin
        current_state = IDLE;
        tx_data = 0;
        rx_data = 0;
        bit_count = 0;
        clock_high = 0;
        SPI_EN = 1;  // Not selected (assuming active low)
        SPI_MOSI = 1'bz;  // Tri-STATE
        SPI_CLK = 0;       // Start low
        data_out = 0;
    end

    // State machine for the transfer
    always_ff @(posedge clk) begin
        if (rst) begin
            // Reset all variables
            current_state <= IDLE;
            tx_data <= 0;
            rx_data <= 0;
            bit_count <= 0;
            clock_high <= 0;
            SPI_EN <= 1;  // Not selected
            SPI_CLK <= 0; // Clock low
        end else begin
            case (current_state)
                IDLE: begin
                    if (SPI_start) begin
                        // Start a new transfer
                        tx_data <= data_in;
                        rx_data <= 0;
                        bit_count <= 0;
                        current_state <= SHIFT;
                        clock_high <= 0;  // Start with clock low
                        SPI_EN <= 0;      // Select the slave (active low)
                    end
                end
                SHIFT: begin
                    if (!clock_high) begin
                        // Rising edge: send next bit
                        if (bit_count < 8) begin
                            // Send the next bit (MSB first)
                            SPI_MOSI <= tx_data[7 - bit_count];
                            // Toggle clock high
                            clock_high <= 1;
                        end else begin
                            // All bits sent; transition to DONE
                            current_state <= DONE;
                            clock_high <= 0;
                        end
                    end
                end
                DONE: begin
                    // Deselect the slave and prepare for next transfer
                    current_state <= IDLE;
                    SPI_EN <= 1;  // Not selected
                    clock_high <= 0;
                end
            endcase
        end
    end

    // Handle falling edge for data capture and clock toggling
    always_ff @(negedge clk) begin
        if (rst) begin
            // Reset
            bit_count <= 0;
        end else begin
            if (current_state == SHIFT && clock_high) begin
                // Capturing data on falling edge
                if (bit_count < 8) begin
                    // Store the received bit at the correct position
                    rx_data[7 - bit_count] <= SPI_MISO;
                    bit_count <= bit_count + 1;
                    // Toggle clock back to low
                    clock_high <= 0;
                end
            end
        end
    end

    // Once all bits are processed, set data_out
    always_ff @(posedge clk) begin
        if (rst) begin
            data_out <= 0;
        end else begin
            if (current_state == DONE) begin
                data_out <= rx_data;
            end
        end
    end

    // Drive the SPI_CLK signal based on the current state
    always_ff @(posedge clk) begin
        if (rst) begin
            SPI_CLK <= 0;  // Start low
        end else begin
            if (current_state == SHIFT) begin
                if (!clock_high) begin
                    SPI_CLK <= 1;  // Rising edge
                end else begin
                    if (bit_count < 8) begin
                        SPI_CLK <= 0;  // Falling edge
                    end
                end
            end else begin
                SPI_CLK <= 0;  // Low in IDLE and DONE states
            end
        end
    end

    // Drive the SPI_MOSI signal
    always_comb begin
        case (current_state)
            IDLE, DONE: SPI_MOSI = 1'bz;  // High Z
            SHIFT: begin
                if (!clock_high) begin
                    // On rising edge, drive the next bit
                    SPI_MOSI = tx_data[7 - bit_count];
                end else begin
                    // During falling edge, no data to drive
                    SPI_MOSI = 1'bz;
                end
            end
        endcase
    end

endmodule