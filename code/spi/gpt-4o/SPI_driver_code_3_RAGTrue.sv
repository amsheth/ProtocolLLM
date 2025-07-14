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
    // SPI configuration parameters
    parameter CPOL = 0; // Clock polarity
    parameter CPHA = 0; // Clock phase

    // Internal signals
    logic [7:0] shift_reg;
    logic [2:0] bit_count;
    logic clk_div;
    logic spi_clk_edge;

    // Clock divider for generating SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 0;
        end else if (SPI_start) begin
            clk_div <= ~clk_div;
        end
    end

    // SPI clock generation based on CPOL
    assign SPI_CLK = (CPOL == 0) ? clk_div : ~clk_div;

    // SPI state machine
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        TRANSMIT = 2'b01,
        RECEIVE = 2'b10
    } spi_state_t;

    spi_state_t curr_state, next_state;

    // State transition logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            curr_state <= IDLE;
        end else begin
            curr_state <= next_state;
        end
    end

    // Next state logic and output logic
    always_comb begin
        next_state = curr_state;
        SPI_EN = 1'b0;
        SPI_MOSI = 1'b0;
        data_out = 8'd0;

        case (curr_state)
            IDLE: begin
                if (SPI_start) begin
                    next_state = TRANSMIT;
                    shift_reg = data_in;
                    SPI_EN = 1'b1;
                    bit_count = 3'd7;
                end
            end

            TRANSMIT: begin
                SPI_EN = 1'b1;
                if (clk_div) begin // Transact on falling edge if CPHA is 0
                    SPI_MOSI = shift_reg[bit_count];
                    if (bit_count == 0) begin
                        next_state = RECEIVE;
                    end else begin
                        bit_count = bit_count - 1;
                    end
                end
            end

            RECEIVE: begin
                SPI_EN = 1'b1;
                if (!clk_div) begin // Capture on rising edge if CPHA is 0
                    shift_reg[bit_count] = SPI_MISO;
                    if (bit_count == 0) begin
                        next_state = IDLE;
                        data_out = shift_reg;
                    end else begin
                        bit_count = bit_count - 1;
                    end
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end
endmodule