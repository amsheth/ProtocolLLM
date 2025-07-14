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

    // Internal signals
    logic [2:0] bit_counter;  // Counter for bits (8 bits per byte)
    logic [7:0] shift_reg;    // Shift register to hold the outgoing and incoming data
    logic clk_divider;        // Clock divider signal
    logic spi_clk_int;        // Internal SPI clock
    logic spi_clk_prev;       // Previous state of internal SPI clock
    logic mosi_out;           // Output for MOSI line
    logic miso_in;            // Input from MISO line

    // State machine states
    typedef enum logic [1:0] {
        IDLE,
        TRANSFER,
        DONE
    } spi_state_t;

    spi_state_t state, next_state;

    // Clock divider to generate SPI clock (assuming clk is much faster than the desired SPI speed)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 1'b0;
        end else begin
            clk_divider <= ~clk_divider; // Toggle every cycle of clk
        end
    end

    // Internal SPI clock generation with CPOL=1
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_int <= 1'b1;
        end else begin
            spi_clk_int <= clk_divider; // Follow the clk_divider signal, starting high due to CPOL=1
        end
    end

    // State machine for SPI transfer
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = TRANSFER;
                end
            end
            TRANSFER: begin
                if (bit_counter == 3'b111) begin // All bits transferred
                    next_state = DONE;
                end
            end
            DONE: begin
                next_state = IDLE; // Go back to idle after transfer is done
            end
        endcase
    end

    // SPI control logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 3'b0;
            shift_reg   <= 8'b0;
            data_out    <= 8'b0;
            mosi_out    <= 1'b0;
            SPI_EN      <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (SPI_start) begin
                        bit_counter <= 3'b0;
                        shift_reg   <= data_in; // Load the data to be sent
                        SPI_EN      <= 1'b1;    // Enable SPI communication
                    end
                end
                TRANSFER: begin
                    if (spi_clk_prev == 1'b1 && spi_clk_int == 1'b0) begin // Falling edge of SPI clock
                        mosi_out <= shift_reg[7]; // Output the MSB on MOSI

                        // Shift the register left and bring in MISO data
                        shift_reg <= {shift_reg[6:0], miso_in};

                        bit_counter <= bit_counter + 1; // Increment bit counter
                    end
                end
                DONE: begin
                    SPI_EN   <= 1'b0;    // Disable SPI communication
                    data_out <= shift_reg; // Output the received data
                end
            endcase

            spi_clk_prev <= spi_clk_int;
        end
    end

    // Assign outputs
    assign SPI_CLK = spi_clk_int;
    assign SPI_MOSI = mosi_out;
    assign miso_in = SPI_MISO;

endmodule