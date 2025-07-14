module SPI_driver(
    input  logic        clk,          // system clk
    input  logic        rst,          // synchronous reset
    input  logic [7:0]  data_in,      // data to send (MSB first)
    input  logic        SPI_MISO,     // MISO signal from slave
    input  logic        SPI_start,    // one-clock strobe to start transfer
    output logic        SPI_MOSI,     // MOSI to slave
    output logic        SPI_CLK,      // SCLK to slave
    output logic        SPI_EN,       // active low SS/EN to slave
    output logic [7:0]  data_out      // data received from slave (MSB first)
);

    typedef enum logic [1:0] {
        IDLE,
        ASSERT_SS,
        TRANSFER,
        DEASSERT_SS
    } state_t;

    state_t state, next_state;

    logic [7:0] shift_out;
    logic [7:0] shift_in;
    logic [2:0] bit_cnt;
    logic       sclk;
    logic       sclk_en;
    logic       sclk_rise;
    logic       sclk_fall;

    // SPI Clock Divider (Change as needed for slower SPI)
    // Here we run SPI_CLK at clk/2 (one clk cycle = half SCLK period)
    logic [0:0] clk_div; // 1-bit toggle for clk/2

    // SCLK clocking
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 1'b0;
        end else if (sclk_en) begin
            clk_div <= ~clk_div;
        end else begin
            clk_div <= 1'b0;
        end
    end

    assign sclk = (state == TRANSFER && sclk_en) ? clk_div : 1'b0;

    // Generate SPI_CLK output (CPOL=0)
    assign SPI_CLK = sclk;

    // Generate SPI_EN (active low): SS goes low only during TRANSFER or ASSERT_SS
    assign SPI_EN = ~((state == ASSERT_SS) || (state == TRANSFER));

    // Edge detection for SCLK (within TRANSFER state)
    always_comb begin
        sclk_rise = 0;
        sclk_fall = 0;
        if (state == TRANSFER && sclk_en) begin
            if (clk_div == 1'b1) // rising edge just happened
                sclk_rise = 1;
            else // falling edge just happened
                sclk_fall = 1;
        end
    end

    // FSM: State transitions
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
            IDLE:         next_state = SPI_start ? ASSERT_SS : IDLE;
            ASSERT_SS:    next_state = TRANSFER;
            TRANSFER:     next_state = (bit_cnt == 3'd7 && sclk_rise) ? DEASSERT_SS : TRANSFER;
            DEASSERT_SS:  next_state = IDLE;
        endcase
    end

    // Bit Counter and SCLK control
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt   <= 3'd0;
            sclk_en   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    bit_cnt <= 3'd0;
                    sclk_en <= 1'b0;
                end
                ASSERT_SS: begin
                    bit_cnt <= 3'd0;
                    sclk_en <= 1'b1;
                end
                TRANSFER: begin
                    sclk_en <= 1'b1;
                    if (sclk_rise) begin
                        if (bit_cnt != 3'd7)
                            bit_cnt <= bit_cnt + 3'd1;
                        else
                            bit_cnt <= bit_cnt;
                    end
                end
                DEASSERT_SS: begin
                    sclk_en <= 1'b0;
                end
            endcase
        end
    end

    // Output shift register (drive MOSI on SCLK falling edge, sample MISO on SCLK rising edge)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_out <= 8'h00;
            shift_in  <= 8'h00;
            SPI_MOSI  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    shift_out <= data_in;
                    shift_in  <= 8'h00;
                    SPI_MOSI  <= data_in[7]; // MSB (first)
                end
                ASSERT_SS: begin
                    shift_out <= data_in;
                    shift_in  <= 8'h00;
                    SPI_MOSI  <= data_in[7];
                end
                TRANSFER: begin
                    // Change data at falling edge (CPHA=1)
                    if (sclk_fall) begin
                        shift_out <= {shift_out[6:0], 1'b0}; // shift out next bit
                        SPI_MOSI  <= shift_out[6];          // next MSB
                    end
                    // Sample at rising edge (CPHA=1)
                    if (sclk_rise) begin
                        shift_in <= {shift_in[6:0], SPI_MISO}; // shift in at MSB first
                    end
                end
                default: ;
            endcase
        end
    end

    // Latch data_out after transfer finished
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'h00;
        end else if (state == DEASSERT_SS) begin
            data_out <= shift_in;
        end
    end

endmodule