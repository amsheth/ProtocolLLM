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
    logic       sclk_rise;
    logic       sclk_fall;

    // CPOL=1, CPHA=1: SCLK idles high, data is sampled on rising edge, changed on falling edge
    assign SPI_CLK = sclk_int;
    assign SPI_EN  = (state == TRANSFER);
    assign data_out = recv_reg;

    // SCLK generation (divide by 2 for SPI clock)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_int <= 1'b1; // CPOL=1, idle high
        end else if (sclk_en) begin
            sclk_int <= ~sclk_int;
        end else begin
            sclk_int <= 1'b1;
        end
    end

    // SCLK edge detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_rise <= 1'b0;
            sclk_fall <= 1'b0;
        end else begin
            sclk_rise <= (sclk_en && ~sclk_int && (state == TRANSFER));
            sclk_fall <= (sclk_en &&  sclk_int && (state == TRANSFER));
        end
    end

    // State machine
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
            IDLE:    if (SPI_start) next_state = LOAD;
            LOAD:    next_state = TRANSFER;
            TRANSFER:if (bit_cnt == 3'd7 && sclk_rise) next_state = DONE;
            DONE:    next_state = IDLE;
        endcase
    end

    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt <= 3'd0;
        end else if (state == LOAD) begin
            bit_cnt <= 3'd0;
        end else if (state == TRANSFER && sclk_rise) begin
            bit_cnt <= bit_cnt + 3'd1;
        end
    end

    // Shift register for MOSI
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'd0;
        end else if (state == LOAD) begin
            shift_reg <= data_in;
        end else if (state == TRANSFER && sclk_fall) begin
            shift_reg <= {shift_reg[6:0], 1'b0};
        end
    end

    // Output MOSI (CPHA=1: change on falling edge, sample on rising edge)
    assign SPI_MOSI = shift_reg[7];

    // Receive register for MISO
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            recv_reg <= 8'd0;
        end else if (state == LOAD) begin
            recv_reg <= 8'd0;
        end else if (state == TRANSFER && sclk_rise) begin
            recv_reg <= {recv_reg[6:0], SPI_MISO};
        end
    end

    // SCLK enable
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_en <= 1'b0;
        end else if (state == LOAD) begin
            sclk_en <= 1'b1;
        end else if (state == DONE) begin
            sclk_en <= 1'b0;
        end
    end

endmodule