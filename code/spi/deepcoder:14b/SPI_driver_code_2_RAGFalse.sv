module SPI_driver (
    input  logic             clk,
    input  logic             rst,
    input  logic [7:0]       data_in,
    input  logic             SPI_MISO,
    input  logic             SPI_start,
    output logic             SPI_MOSI,
    output logic             SPI_CLK,
    output logic             SPI_EN,
    output logic [7:0]       data_out
);

    // State machine states
    enum {
        IDLE,
        Transmitting,
        Receiving,
        Done
    } state, next_state;

    // Internal signals
    logic [2:0] tx_counter;  // For transmitting data_in
    logic [2:0] rx_counter;  // For receiving data_out
    logic tx_clk;            // To generate the clock for transmission
    logic [7:0] received_data;

    always_ff @ (posedge clk) begin
        if (rst) begin
            state          <= IDLE;
            SPI_CLK       <= 1'b0;
            tx_counter    <= 3'b000;
            rx_counter    <= 3'b000;
            tx_clk        <= 1'b0;
            received_data <= 8'h00;
            data_out      <= 8'h00;
            SPI_EN        <= 1'b1;  // Initially disabled
        end else begin
            state          <= next_state;
            tx_counter    <= tx_counter + 3'b001;  // Increment for each bit
            rx_counter    <= rx_counter + 3'b001;
            tx_clk        <= ~tx_clk;              // Toggle clock
        end
    end

    always_comb begin
        case (state)
            IDLE: begin
                SPI_CLK       = 1'b0;  // Clock is low in idle state
                SPI_EN        = 1'b1;  // Initially disabled
                tx_counter    = 3'b000;
                rx_counter    = 3'b000;
                received_data = 8'h00;

                if (SPI_start) begin
                    next_state = Transmitting;
                    tx_clk     = 1'b0;  // Start clock on rising edge
                end else begin
                    next_state = IDLE;
                end
            end

            Transmitting: begin
                SPI_CLK       = tx_clk;    // Generate clock based on tx_clk
                SPI_EN        = 1'b0;      // Enable the device (assuming active low)
                tx_counter    = tx_counter;

                if (tx_counter == 3'h7) begin
                    next_state = Receiving;
                end else begin
                    next_state = Transmitting;
                end

                // Send data on rising edge of clock
                if (tx_clk && state == Transmitting) begin
                    SPI_MOSI = data_in[tx_counter];
                end
            end

            Receiving: begin
                SPI_CLK       = tx_clk;    // Continue clock
                SPI_EN        = 1'b0;

                if (rx_counter == 3'h7) begin
                    next_state = Done;
                end else begin
                    next_state = Receiving;
                end

                // Receive data on rising edge of clock
                if (tx_clk && state == Receiving) begin
                    received_data[rx_counter] = SPI_MISO;
                end
            end

            Done: begin
                SPI_CLK       = 1'b0;     // Stop clock
                SPI_EN        = 1'b1;      // Disable the device
                data_out      = received_data;
                next_state    = IDLE;
            end
        endcase
    end

endmodule