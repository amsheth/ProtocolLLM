module SPI_driver(
    input logic clk,          // System Clock
    input logic rst,          // Active high synchronous reset
    input logic [7:0] data_in,// Data to be transmitted
    input logic SPI_MISO,     // Master In Slave Out (Input)
    input logic SPI_start,    // Start signal for transmission
    output logic SPI_MOSI,    // Master Out Slave In (Output)
    output logic SPI_CLK,     // SPI Clock Output
    output logic SPI_EN,      // Enable signal for the slave device
    output logic [7:0] data_out// Data received from the slave
);

    localparam CLK_DIV = 8;   // Assuming a clock divider to generate SPI clock (adjust as needed)
    
    typedef enum logic [2:0] {
        IDLE,
        START,
        TRANSFER,
        DONE
    } state_t;

    state_t state, next_state;
    logic [7:0] bit_counter;
    logic [7:0] shift_reg_tx;
    logic [7:0] shift_reg_rx;
    logic clk_div_cnt;
    logic spi_clk_int;

    // Clock Divider to generate SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            clk_div_cnt <= '0;
        else if (SPI_EN)
            clk_div_cnt <= clk_div_cnt + 1'b1;
    end

    assign spi_clk_int = clk_div_cnt[2]; // Assuming CLK_DIV is 8, this will toggle every 4 cycles of clk

    // State Machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (SPI_start)
                    next_state = START;
            end
            START: begin
                next_state = TRANSFER;
            end
            TRANSFER: begin
                if (bit_counter == 8'd7) // All bits transferred
                    next_state = DONE;
            end
            DONE: begin
                next_state = IDLE; // Go back to idle after transfer is done
            end
        endcase
    end

    // State Machine Actions
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= 1'b0;
            SPI_EN <= 1'b0;
            bit_counter <= '0;
            shift_reg_tx <= '0;
            data_out <= '0;
        end else begin
            case (state)
                IDLE: begin
                    SPI_CLK <= 1'b0; // Clock is idle low
                    SPI_EN <= 1'b0; // Disable slave device
                    if (SPI_start) begin
                        shift_reg_tx <= data_in; // Load data to be transmitted
                        bit_counter <= '0;
                        SPI_EN <= 1'b1; // Enable slave device
                    end
                end
                START: begin
                    SPI_CLK <= spi_clk_int; // Start clock generation
                end
                TRANSFER: begin
                    if (spi_clk_int) begin // Data sampled on rising edge of SPI_CLK
                        shift_reg_rx <= {shift_reg_rx[6:0], SPI_MISO}; // Shift in received data
                        SPI_MOSI <= shift_reg_tx[7]; // Output MSB of transmit data
                        shift_reg_tx <= {1'b0, shift_reg_tx[7:1]}; // Shift out transmitted data
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
                DONE: begin
                    SPI_CLK <= 1'b0; // Stop clock generation
                    data_out <= shift_reg_rx; // Output received data
                    SPI_EN <= 1'b0; // Disable slave device
                end
            endcase
        end
    end

endmodule