//---------------------------------------------------------------
// Simple SPI-MASTER driver (MODE-0: CPOL=0, CPHA=0)
// • Sends 8-bit framed data on MOSI and receives 8-bit data
// • Programmable serial clock division via CLK_DIV
//---------------------------------------------------------------
module SPI_driver #(
    parameter int CLK_DIV = 4         // System-clock cycles per half SCLK period (must be >1)
)(
    input  logic        clk,          // System clock
    input  logic        rst,          // Active-high synchronous reset
    input  logic [7:0]  data_in,      // Byte to transmit
    input  logic        SPI_MISO,     // Serial data from slave
    input  logic        SPI_start,    // 1-pulse: start new transfer
    output logic        SPI_MOSI,     // Serial data to slave
    output logic        SPI_CLK,      // Serial clock to slave (MODE-0)
    output logic        SPI_EN,       // Active-low chip-select (/SS)
    output logic [7:0]  data_out      // Byte just received
);

    // ----------------------------------------------------------
    // Local types / constants
    // ----------------------------------------------------------
    typedef enum logic [1:0] {IDLE, LOAD, TRANSFER, DONE} state_t;

    // ----------------------------------------------------------
    // Registers / wires
    // ----------------------------------------------------------
    state_t     state,  nxt_state;

    logic [7:0] shifter_tx;           // Shift register (outgoing)
    logic [7:0] shifter_rx;           // Shift register (incoming)

    logic [2:0] bit_cnt;              // Counts 7..0
    logic [$clog2(CLK_DIV)-1:0] div_cnt;   // SCLK divider counter
    logic       sclk_int;             // Internal SCLK before CPOL addition
    logic       sclk_rise;            // 1-clk pulse on SCLK rising edge
    logic       sclk_fall;            // 1-clk pulse on SCLK falling edge

    // ----------------------------------------------------------
    // Divider : generate internal SCLK (50 % duty)
    // ----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_cnt  <= '0;
            sclk_int <= 1'b0;
        end
        else if (state == TRANSFER) begin
            if (div_cnt == CLK_DIV-1) begin
                div_cnt  <= '0;
                sclk_int <= ~sclk_int;
            end
            else
                div_cnt <= div_cnt + 1'b1;
        end
        else begin
            div_cnt  <= '0;
            sclk_int <= 1'b0;  // Idle low (CPOL=0)
        end
    end

    // Detect internal SCLK edges (for sampling / driving)
    assign sclk_rise = (state == TRANSFER) && (div_cnt == CLK_DIV-1) && (sclk_int == 1'b0);
    assign sclk_fall = (state == TRANSFER) && (div_cnt == CLK_DIV-1) && (sclk_int == 1'b1);

    // ----------------------------------------------------------
    // FSM : controls sequencing of a single 8-bit frame
    // ----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= nxt_state;
    end

    always_comb begin
        nxt_state = state;
        case (state)
            IDLE   : if (SPI_start)    nxt_state = LOAD;
            LOAD   :                  nxt_state = TRANSFER;
            TRANSFER:
                     if ((bit_cnt == 3'd0) && sclk_rise)
                                          nxt_state = DONE;
            DONE   :                  nxt_state = IDLE;
        endcase
    end

    // ----------------------------------------------------------
    // Bit counter
    // ----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bit_cnt <= 3'd7;
        else if (state == LOAD)
            bit_cnt <= 3'd7;
        else if (state == TRANSFER && sclk_rise)
            bit_cnt <= bit_cnt - 1'b1;
    end

    // ----------------------------------------------------------
    // Shift-registers : transmit on falling edge, receive on rising edge
    // ----------------------------------------------------------
    // Transmit path (MOSI) ------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            shifter_tx <= '0;
        else if (state == LOAD)
            shifter_tx <= data_in;
        else if (state == TRANSFER && sclk_fall)
            shifter_tx <= {shifter_tx[6:0], 1'b0};  // Shift left, MSB first
    end
    assign SPI_MOSI = shifter_tx[7];     // Drive MSB when CPHA=0

    // Receive path (MISO) -------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            shifter_rx <= '0;
        else if (state == LOAD)
            shifter_rx <= '0;
        else if (state == TRANSFER && sclk_rise)
            shifter_rx <= {shifter_rx[6:0], SPI_MISO}; // Sample at rising edge
    end

    // ----------------------------------------------------------
    // Data-out latch
    // ----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            data_out <= '0;
        else if (state == DONE)
            data_out <= shifter_rx;
    end

    // ----------------------------------------------------------
    // SPI control outputs
    // ----------------------------------------------------------
    assign SPI_CLK = sclk_int;           // CPOL=0   (idle low)
    assign SPI_EN  = (state == TRANSFER || state == LOAD) ? 1'b0  // active-low
                                                          : 1'b1; // de-asserted otherwise
endmodule