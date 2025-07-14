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
    logic       sclk_int;
    logic       sclk_en;
    logic       mosi_int;
    logic       en_int;

    // CPOL=0, CPHA=1: SCLK idles low, data sampled on rising edge, changed on falling edge

    // SCLK generation (one SCLK per two clk cycles)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_int <= 1'b0;
        end else if (sclk_en) begin
            sclk_int <= ~sclk_int;
        end else begin
            sclk_int <= 1'b0;
        end
    end

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            shift_reg <= 8'd0;
            recv_reg  <= 8'd0;
            bit_cnt   <= 3'd7;
            mosi_int  <= 1'b0;
            en_int    <= 1'b1;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    en_int   <= 1'b1;
                    mosi_int <= 1'b0;
                    if (SPI_start) begin
                        shift_reg <= data_in;
                        bit_cnt   <= 3'd7;
                    end
                end
                LOAD: begin
                    en_int   <= 1'b0;
                    mosi_int <= shift_reg[7];
                end
                TRANSFER: begin
                    en_int <= 1'b0;
                    // CPHA=1: Change MOSI on falling edge, sample MISO on rising edge
                    if (sclk_int == 1'b0) begin // falling edge
                        mosi_int  <= shift_reg[bit_cnt];
                    end else begin // rising edge
                        recv_reg[bit_cnt] <= SPI_MISO;
                        if (bit_cnt != 0)
                            bit_cnt <= bit_cnt - 1;
                    end
                end
                DONE: begin
                    en_int   <= 1'b1;
                    mosi_int <= 1'b0;
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        sclk_en    = 1'b0;
        case (state)
            IDLE: begin
                if (SPI_start)
                    next_state = LOAD;
            end
            LOAD: begin
                next_state = TRANSFER;
            end
            TRANSFER: begin
                sclk_en = 1'b1;
                if ((bit_cnt == 0) && (sclk_int == 1'b1))
                    next_state = DONE;
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    assign SPI_MOSI = mosi_int;
    assign SPI_CLK  = sclk_int;
    assign SPI_EN   = en_int;
    assign data_out = recv_reg;

endmodule