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
    logic       clk_div;
    logic       clk_en;

    // SPI clock generation (divide by 2 for demonstration)
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            clk_div <= 1'b0;
        else if (clk_en)
            clk_div <= ~clk_div;
        else
            clk_div <= 1'b0;
    end

    // SPI state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:    if (SPI_start) next_state = LOAD;
            LOAD:    next_state = TRANSFER;
            TRANSFER:if (bit_cnt == 3'd7 && clk_div && clk_en) next_state = DONE;
            DONE:    next_state = IDLE;
        endcase
    end

    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bit_cnt <= 3'd0;
        else if (state == LOAD)
            bit_cnt <= 3'd0;
        else if (state == TRANSFER && clk_div && clk_en)
            bit_cnt <= bit_cnt + 1'b1;
    end

    // Shift register for MOSI
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            shift_reg <= 8'd0;
        else if (state == LOAD)
            shift_reg <= data_in;
        else if (state == TRANSFER && clk_div && clk_en)
            shift_reg <= {shift_reg[6:0], 1'b0};
    end

    // Receive register for MISO
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            recv_reg <= 8'd0;
        else if (state == LOAD)
            recv_reg <= 8'd0;
        else if (state == TRANSFER && clk_en && !clk_div) // sample on leading edge
            recv_reg <= {recv_reg[6:0], SPI_MISO};
    end

    // Output assignments
    assign SPI_MOSI = shift_reg[7];
    assign SPI_CLK  = (state == TRANSFER && clk_en) ? clk_div : 1'b0; // CPOL=0
    assign SPI_EN   = (state == TRANSFER || state == LOAD) ? 1'b0 : 1'b1; // Active low
    assign data_out = (state == DONE) ? recv_reg : 8'd0;

    // Enable SPI clock only during transfer
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            clk_en <= 1'b0;
        else if (state == LOAD)
            clk_en <= 1'b1;
        else if (state == DONE)
            clk_en <= 1'b0;
    end

endmodule