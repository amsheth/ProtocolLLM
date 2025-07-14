//------------------------------------------------------------
// Simple SPI master driver
// Mode : CPOL = 0 , CPHA = 0      (SPI-Mode-0)
// Word : 8-bit, MSB first
// Note : SPI_EN is active LOW
//------------------------------------------------------------
module SPI_driver
#(
    // System-clock-to-SPI-clock divider (must be even, ≥2)
    parameter int CLK_DIV = 4
)(
    input  logic       clk,        // system clock
    input  logic       rst,        // asynchronous reset, active high
    input  logic [7:0] data_in,    // byte to transmit
    input  logic       SPI_MISO,   // data from slave
    input  logic       SPI_start,  // pulse to start a transfer

    output logic       SPI_MOSI,   // data to slave
    output logic       SPI_CLK,    // generated SPI clock
    output logic       SPI_EN,     // chip-select  (active low)
    output logic [7:0] data_out    // byte received
);

    //--------------------------------------------------------
    // Local parameters / FSM states
    //--------------------------------------------------------
    localparam  IDLE     = 2'b00,
                XFER     = 2'b01,
                DONE     = 2'b10;

    //--------------------------------------------------------
    // Registers / wires
    //--------------------------------------------------------
    logic [1:0]                     state, next_state;

    // clock divider
    logic [$clog2(CLK_DIV)-1:0]     clk_cnt;
    logic                           sclk, sclk_prev;
    logic                           sclk_rise, sclk_fall;

    // shift registers
    logic [7:0]                     tx_reg;
    logic [7:0]                     rx_reg;
    logic [2:0]                     bit_cnt;       // counts remaining bits

    //--------------------------------------------------------
    // State machine
    //--------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE  : if (SPI_start)                       next_state = XFER;
            XFER  : if (sclk_rise && (bit_cnt == 3'd0)) next_state = DONE;
            DONE  :                                        next_state = IDLE;
            default:                                      next_state = IDLE;
        endcase
    end

    //--------------------------------------------------------
    // SPI clock generation  (CPOL = 0  → idle low)
    //--------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_cnt <= '0;
            sclk    <= 1'b0;
        end
        else begin
            if (state == XFER) begin
                if (clk_cnt == CLK_DIV-1) begin
                    clk_cnt <= '0;
                    sclk    <= ~sclk;            // toggle SPI clock
                end else begin
                    clk_cnt <= clk_cnt + 1'b1;
                end
            end
            else begin
                clk_cnt <= '0;
                sclk    <= 1'b0;                 // idle level
            end
        end
    end

    //--------------------------------------------------------
    // Detect rises / falls of the generated SPI clock
    //--------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            sclk_prev <= 1'b0;
        else
            sclk_prev <= sclk;
    end

    assign sclk_rise =  ( sclk & ~sclk_prev);    // 0 → 1
    assign sclk_fall =  (~sclk &  sclk_prev);    // 1 → 0

    //--------------------------------------------------------
    // Shift registers & bit counter
    //  CPHA = 0  →  shift out on falling edge, sample on rising edge
    //--------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_reg   <= '0;
            rx_reg   <= '0;
            bit_cnt  <= 3'd7;
            SPI_MOSI<= 1'b0;
            data_out<= '0;
        end else begin
            case (state)
                IDLE : begin
                    if (SPI_start) begin
                        tx_reg   <= data_in;     // load byte to transmit
                        rx_reg   <= '0;
                        bit_cnt  <= 3'd7;
                        SPI_MOSI <= data_in[7];  // present first (MSB) before 1st rising edge
                    end
                end

                XFER : begin
                    // Shift out next bit (prepare MOSI) on SPI clock falling edge
                    if (sclk_fall) begin
                        tx_reg   <= {tx_reg[6:0], 1'b0};
                        SPI_MOSI <= tx_reg[6];
                    end

                    // Sample MISO on SPI clock rising edge
                    if (sclk_rise) begin
                        rx_reg   <= {rx_reg[6:0], SPI_MISO};
                        if (bit_cnt != 3'd0)
                            bit_cnt <= bit_cnt - 1'b1;
                    end
                end

                DONE : begin
                    data_out <= rx_reg;          // make received byte available
                end
            endcase
        end
    end

    //--------------------------------------------------------
    // Outputs
    //--------------------------------------------------------
    assign SPI_CLK = sclk;                       // CPOL = 0
    assign SPI_EN  = (state == XFER) ? 1'b0 : 1'b1;   // active low

endmodule