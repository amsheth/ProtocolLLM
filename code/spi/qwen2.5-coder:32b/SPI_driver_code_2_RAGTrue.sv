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
    logic spi_clk_prev;       // Previous state of internal SPI clock for edge detection
    logic mosi_out;           // Output to MOSI line
    logic miso_in;            // Input from MISO line
    logic start_flag;         // Flag to indicate the start of a transaction

    // Clock divider (simple 2x divider)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 1'b0;
        end else begin
            clk_divider <= ~clk_divider;
        end
    end

    // Internal SPI clock generation with CPOL=0 and CPHA=1
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_int <= 1'b0;  // Idle low
        end else begin
            spi_clk_int <= clk_divider;
        end
    end

    // Edge detection for sampling MISO on falling edge of SPI_CLK
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_prev <= 1'b0;
        end else begin
            spi_clk_prev <= spi_clk_int;
        end
    end

    // SPI transaction state machine
    typedef enum logic [2:0] {
        IDLE,
        LOAD_DATA,
        TRANSFER,
        SAMPLE_MISO,
        DONE
    } spi_state_t;

    spi_state_t state, next_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // State transition logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (SPI_start && !start_flag) begin
                    next_state = LOAD_DATA;
                end
            end
            LOAD_DATA: begin
                next_state = TRANSFER;
            end
            TRANSFER: begin
                if (bit_counter == 3'b111) begin // All bits transferred
                    next_state = SAMPLE_MISO;
                end else begin
                    next_state = TRANSFER;
                end
            end
            SAMPLE_MISO: begin
                next_state = DONE;
            end
            DONE: begin
                if (!SPI_start) begin
                    next_state = IDLE;
                end
            end
        endcase
    end

    // State action logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 3'b000;
            shift_reg <= 8'b0;
            mosi_out <= 1'b0;
            miso_in <= 1'b0;
            data_out <= 8'b0;
            SPI_EN <= 1'b0;
            start_flag <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (SPI_start && !start_flag) begin
                        bit_counter <= 3'b000;
                        shift_reg <= data_in; // Load the data to be sent
                        SPI_EN <= 1'b1;      // Enable SPI communication
                        start_flag <= 1'b1;
                    end
                end
                LOAD_DATA: begin
                    bit_counter <= 3'b000;
                    shift_reg <= data_in; // Load the data to be sent
                end
                TRANSFER: begin
                    if (spi_clk_prev && !spi_clk_int) begin // Falling edge of SPI_CLK
                        mosi_out <= shift_reg[7];           // Output MSB on MOSI
                        shift_reg <= {shift_reg[6:0], 1'b0}; // Shift left the register
                        bit_counter <= bit_counter + 3'b001; // Increment bit counter
                    end
                end
                SAMPLE_MISO: begin
                    if (spi_clk_prev && !spi_clk_int) begin // Falling edge of SPI_CLK
                        miso_in <= SPI_MISO;               // Sample MISO on falling edge
                        data_out <= {shift_reg[6:0], miso_in}; // Store the received bit
                    end
                end
                DONE: begin
                    SPI_EN <= 1'b0; // Disable SPI communication
                    start_flag <= 1'b0;
                end
            endcase
        end
    end

    // Assign outputs
    assign SPI_CLK = spi_clk_int;
    assign SPI_MOSI = mosi_out;

endmodule