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
    parameter CPOL = 0;  // Clock Polarity
    parameter CPHA = 1;  // Clock Phase

    // Internal signals
    logic [2:0] bit_counter;
    logic [7:0] shift_reg;

    // State machine states
    typedef enum logic [1:0] {
        IDLE,
        TRANSFER,
        COMPLETE
    } state_t;

    state_t current_state, next_state;

    // Clock generation logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= CPOL;  // Reset clock to the idle state as per the CPOL
        end else begin
            // Generate clock based on CPHA and CPOL
            if (current_state == TRANSFER && (bit_counter == 0 || CPHA)) begin
                SPI_CLK <= ~SPI_CLK;
            end
        end
    end

    // State machine logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            bit_counter <= 3'd0;
            shift_reg <= 8'd0;
            data_out <= 8'd0;
            SPI_EN <= 1'b0;
        end else begin
            current_state <= next_state;
            if (current_state == TRANSFER) begin
                if (SPI_CLK != CPOL) begin // Ensure data is sampled on the correct edge
                    shift_reg <= {shift_reg[6:0], SPI_MISO};
                end
            end
            if (next_state == COMPLETE && current_state != COMPLETE) begin
                data_out <= shift_reg;  // Update data_out when transfer is complete
            end
        end
    end

    // Next state logic and output logic
    always_comb begin
        next_state = current_state;
        SPI_EN = 1'b0;
        SPI_MOSI = data_in[7 - bit_counter];

        unique case (current_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = TRANSFER;
                    shift_reg = data_in;  // Load data to shift register
                    bit_counter = 3'd0;
                end
            end

            TRANSFER: begin
                SPI_EN = 1'b1;
                if (SPI_CLK == CPOL) begin // Data is changed on the opposite edge of sampling point
                    bit_counter = bit_counter + 1;
                    if (bit_counter == 3'd7) begin
                        next_state = COMPLETE;
                    end
                end
            end

            COMPLETE: begin
                next_state = IDLE; // Go back to IDLE after complete
            end

            default: next_state = IDLE;
        endcase
    end
endmodule