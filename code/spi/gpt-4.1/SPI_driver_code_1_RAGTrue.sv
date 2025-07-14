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

    // Parameters: CPOL=1 (idle high), CPHA=0 (data changes on trailing, sampled on leading edge)
    parameter CPOL = 1;
    parameter CPHA = 0;
    parameter DATA_WIDTH = 8;

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        TRANSFER,
        DONE
    } spi_state_t;

    spi_state_t state, next_state;

    logic [DATA_WIDTH-1:0] shift_reg;
    logic [DATA_WIDTH-1:0] recv_reg;
    logic [3:0]            bit_cnt;
    logic                  sclk;
    logic                  sclk_int;
    logic                  en;

    // Clock Divider for SPI (Assume SCLK is half freq of clk for simplicity)
    logic clk_div;
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            clk_div <= 1'b0;
        end else if (en && state==TRANSFER) begin
            clk_div <= ~clk_div;
        end else begin
            clk_div <= 1'b0;
        end
    end

    // Edge detect for sampling and shifting
    logic clk_div_r;
    always_ff @(posedge clk or posedge rst) begin
        if(rst) clk_div_r <= CPOL;
        else    clk_div_r <= clk_div;
    end

    wire sclk_posedge = (clk_div == 1'b1) && (clk_div_r == 1'b0);
    wire sclk_negedge = (clk_div == 1'b0) && (clk_div_r == 1'b1);

    // State Machine
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
            TRANSFER:if (bit_cnt == DATA_WIDTH) next_state = DONE;
            DONE:    next_state = IDLE;
        endcase
    end

    // Control logic
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            shift_reg <= '0;
            recv_reg  <= '0;
            bit_cnt   <= '0;
            sclk      <= CPOL;
            en        <= 1'b0;
            data_out  <= 8'h00;
        end else begin
            case(state)
                IDLE: begin
                    shift_reg <= data_in;
                    recv_reg  <= '0;
                    bit_cnt   <= 4'd0;
                    sclk      <= CPOL;
                    en        <= 1'b0;
                end
                LOAD: begin
                    shift_reg <= data_in;
                    bit_cnt   <= 4'd0;
                    sclk      <= CPOL;
                    en        <= 1'b1;
                end
                TRANSFER: begin
                    en <= 1'b1;
                    // For CPOL=1, idle is high. CPHA=0, sample on leading, shift on trailing.
                    // Leading edge for CPOL=1 is falling edge.
                    if(sclk_negedge) begin
                        // Shift out data on trailing edge
                        shift_reg <= {shift_reg[DATA_WIDTH-2:0], 1'b0};
                        bit_cnt   <= bit_cnt + 1'b1;
                    end
                    if(sclk_posedge) begin
                        // Sample data in on leading edge
                        recv_reg <= {recv_reg[DATA_WIDTH-2:0], SPI_MISO};
                    end
                    // Toggle SCLK in transfer state only
                    sclk <= clk_div;
                end
                DONE: begin
                    data_out <= recv_reg;
                    en       <= 1'b0;
                    sclk     <= CPOL;
                end
            endcase
        end
    end

    // Outputs
    assign SPI_CLK = (state == TRANSFER) ? sclk : CPOL;
    assign SPI_EN  = en;
    assign SPI_MOSI= shift_reg[DATA_WIDTH-1];

endmodule