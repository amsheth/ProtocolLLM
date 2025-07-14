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

    // SPI parameters
    // CPOL = 0: Clock idle low
    // CPHA = 0: Data sampled on leading (rising) edge (so data must be stable on falling edge)

    typedef enum logic [1:0] {
        IDLE, 
        LOAD, 
        TRANSFER, 
        DONE
    } state_t;

    state_t state, next_state;

    logic [7:0] shift_reg_tx;
    logic [7:0] shift_reg_rx;
    logic [2:0] bit_cnt;
    logic       sclk_int;
    logic       sclk_en;
    logic       mosi_int;
    logic       en_int;

    // SPI clock generation (one SCLK cycle per bit)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sclk_int  <= 1'b0;
            sclk_en   <= 1'b0;
        end else if (state == TRANSFER) begin
            sclk_en   <= 1'b1;
            sclk_int  <= ~sclk_int;
        end else begin
            sclk_int  <= 1'b0; // Idle low for CPOL=0
            sclk_en   <= 1'b0;
        end
    end

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            bit_cnt     <= 3'd7;
            shift_reg_tx<= 8'd0;
            shift_reg_rx<= 8'd0;
            en_int      <= 1'b0;
            mosi_int    <= 1'b0;
            data_out    <= 8'd0;
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    en_int      <= 1'b1; // SPI_EN active low (assume active low user can invert as needed)
                    shift_reg_rx<= 8'd0;
                    if (SPI_start) begin
                        shift_reg_tx <= data_in;
                        bit_cnt      <= 3'd7;
                        mosi_int     <= data_in[7];
                    end else begin
                        mosi_int     <= 1'b0;
                    end
                end
                LOAD: begin
                    en_int   <= 1'b0; // select slave (active low)
                    mosi_int <= shift_reg_tx[7];
                end
                TRANSFER: begin
                    en_int <= 1'b0;
                    // SCLK transitions -- CPOL=0, CPHA=0: sample on rising edge
                    if (sclk_en && sclk_int==1'b1) begin  // rising edge: sample input
                        shift_reg_rx <= {shift_reg_rx[6:0], SPI_MISO};
                        if (bit_cnt==0) begin
                            data_out <= {shift_reg_rx[6:0], SPI_MISO};
                        end
                    end
                    if (sclk_en && sclk_int==1'b0) begin  // falling edge: change MOSI
                        if (bit_cnt != 0) begin
                            shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};
                            mosi_int     <= shift_reg_tx[6];
                            bit_cnt      <= bit_cnt - 3'd1;
                        end
                    end
                end
                DONE: begin
                    en_int   <= 1'b1; // deselect slave
                    mosi_int <= 1'b0;
                end
            endcase
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE:      if (SPI_start) next_state = LOAD;
            LOAD:      next_state = TRANSFER;
            TRANSFER:  if ((bit_cnt==0) && (sclk_en && sclk_int==1'b1)) next_state = DONE;
            DONE:      next_state = IDLE;
        endcase
    end

    // Outputs
    assign SPI_MOSI = mosi_int;
    assign SPI_EN   = en_int;
    assign SPI_CLK  = sclk_int;

endmodule