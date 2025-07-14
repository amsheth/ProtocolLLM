module spi_master (
    input wire system_clock,
    output reg mosi,
    output reg sclk,
    output reg cs_n,
    input wire [7:0] data_to_send
);

reg [2:0] bit_counter; // Counter to track the number of bits sent (0-7)
reg current_bit_value;

always @ (posedge system_clock) begin
    if (!cs_n) begin // If we're already transmitting, continue
        if (bit_counter < 8) begin
            // Send the next bit
            mosi <= data_to_send[7 - bit_counter]; // Assuming MSB first
            sclk <= !sclk; // Toggle the clock
            bit_counter++;
        end else begin
            // All bits sent, deassert CS and reset counters
            cs_n <= 1;
            sclk <= 0;
            bit_counter <= 0;
        end
    end else begin
        // If not transmitting, prepare for transmission
        if (start_transmit) begin // Assume start_transmit is a control signal
            cs_n <= 0; // Select the slave
            bit_counter <= 0;
            sclk <= 0; // Initialize clock
        end
    end
end

// Note: You would need to add logic to trigger the transmission, perhaps with a start button or another control signal.
// Also, in practice, you might want to handle the clock more carefully, ensuring it oscillates properly.

endmodule