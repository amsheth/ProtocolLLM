module SPI_driver(
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  data_in,
    input  logic        SPI_MISO,
    input  logic        SPI_start,
    output logic        SPI_MOSI,
    output logic        SPI_CLK,
    output logic        SPI_EN,
    output logic [7:0]  data_out
);

    typedef enum logic [1:0] {IDLE, LOAD, TRANSFER, DONE} state_t;
    state_t state, next_state;

    logic [7:0] shift_reg;
    logic [7:0] recv_reg;
    logic [2:0] bit_cnt;
    logic       spi_clk_int;
    logic       spi_clk_en;

    // CPOL=1, CPHA=0: SPI_CLK idles high, data is sampled on leading (falling) edge, changed on trailing (rising) edge

    // SPI clock generation (divide by 2 for demonstration)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_int <= 1'b1; // CPOL=1, idle high
        end else if (spi_clk_en) begin
            spi_clk_int <= ~spi_clk_int;
        end else begin
            spi_clk_int <= 1'b1; // CPOL=1, idle high
        end
    end

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            shift_reg <= 8'd0;
            recv_reg  <= 8'd0;
            bit_cnt   <= 3'd7;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    shift_reg <= 8'd0;
                    recv_reg  <= 8'd0;
                    bit_cnt   <= 3'd7;
                end
                LOAD: begin
                    shift_reg <= data_in;
                    bit_cnt   <= 3'd7;
                end
                TRANSFER: begin
                    // CPHA=0: Output data on trailing (rising) edge, sample on leading (falling) edge
                    if (spi_clk_en && !spi_clk_int) begin // falling edge: sample MISO
                        recv_reg[bit_cnt] <= SPI_MISO;
                    end
                    if (spi_clk_en && spi_clk_int) begin // rising edge: shift out next bit
                        if (bit_cnt != 0) begin
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            bit_cnt   <= bit_cnt - 1;
                        end
                    end
                end
                DONE: begin
                    // nothing
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        spi_clk_en = 1'b0;
        case (state)
            IDLE: begin
                if (SPI_start)
                    next_state = LOAD;
            end
            LOAD: begin
                next_state = TRANSFER;
            end
            TRANSFER: begin
                spi_clk_en = 1'b1;
                if ((bit_cnt == 0) && (spi_clk_en && spi_clk_int)) // after last bit shifted out
                    next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    // SPI signals
    assign SPI_EN   = (state == TRANSFER) ? 1'b0 : 1'b1; // Active low
    assign SPI_CLK  = spi_clk_int;
    assign SPI_MOSI = shift_reg[7];
    assign data_out = recv_reg;

endmodule