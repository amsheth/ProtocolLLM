// -----------------------------------------------------------------------------
// Simple SPI MASTER driver (Mode-1 : CPOL = 0 , CPHA = 1)
//    ‑ Idle value of SCLK  : ‘0’
//    ‑ First edge (after EN asserted) is a rising edge
//    ‑ MOSI is changed on every rising edge
//    ‑ MISO is sampled   on every falling edge
//
// NOTES
//   • Parameter CLK_DIV lets you generate a slower serial clock:
//         f_SPI = f_clk / (2*CLK_DIV)
//   • SPI_EN is driven active-low while a transfer is in progress.
// -----------------------------------------------------------------------------
module SPI_driver #(
    parameter integer CLK_DIV = 4                // ≥2, even division of clk
)(
    input  logic        clk,                     // system clock
    input  logic        rst,                     // synchronous reset, active-high
    input  logic [7:0]  data_in,                 // byte to transmit
    input  logic        SPI_MISO,                // serial data from the slave
    input  logic        SPI_start,               // 1-clk-wide start pulse
    output logic        SPI_MOSI,                // serial data to the slave
    output logic        SPI_CLK,                 // serial clock (CPOL=0)
    output logic        SPI_EN,                  // active-low slave-select
    output logic [7:0]  data_out                 // byte just received
);

    // ---------------------------------------------------------
    // Local registers / wires
    // ---------------------------------------------------------
    typedef enum logic [1:0] {IDLE, ASSERT_SS, TRANSFER, DONE} state_t;
    state_t          state, next_state;

    logic [$clog2(CLK_DIV)-1:0] clk_cnt;         // clock divider counter
    logic                        clk_edge;       // 1-clk-wide tick every half SPI period
    logic  [7:0]                 tx_shift;       // transmit shift-register
    logic  [7:0]                 rx_shift;       // receive  shift-register
    logic  [2:0]                 bit_cnt;        // counts 0->7 bits transferred
    logic                        sclk_int;       // internal SCLK signal

    // ---------------------------------------------------------
    // Clock Divider : generates `clk_edge`
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            clk_cnt  <= '0;
            clk_edge <= 1'b0;
        end
        else begin
            if (state == TRANSFER) begin
                if (clk_cnt == (CLK_DIV-1)) begin        // reached half period
                    clk_cnt  <= '0;
                    clk_edge <= 1'b1;
                end else begin
                    clk_cnt  <= clk_cnt + 1'b1;
                    clk_edge <= 1'b0;
                end
            end
            else begin
                clk_cnt  <= '0;
                clk_edge <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------
    // FSM : controls the whole transaction
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        unique case (state)
            IDLE :       if (SPI_start)            next_state = ASSERT_SS;
            ASSERT_SS:   next_state = TRANSFER;     // one half-period of SCLK still low
            TRANSFER:    if ((bit_cnt == 3'd7) &&  // last bit done after two edges
                           (clk_edge && (sclk_int==1'b0)))
                           next_state = DONE;
            DONE:        next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

    // ---------------------------------------------------------
    // Shift registers & counters
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            tx_shift <= 8'h00;
            rx_shift <= 8'h00;
            bit_cnt  <= 3'd0;
        end
        else begin
            case (state)
                IDLE : begin
                    bit_cnt  <= 3'd0;
                    if (SPI_start)
                        tx_shift <= data_in;       // preload tx data
                end

                ASSERT_SS : begin
                    // keep counters cleared, wait for first rising edge
                    bit_cnt <= 3'd0;
                end

                TRANSFER : begin
                    if (clk_edge) begin
                        // Rising edge : drive next MOSI bit
                        if (sclk_int == 1'b0) begin   // just rose to '1'
                            SPI_MOSI <= tx_shift[7];
                            tx_shift  <= {tx_shift[6:0],1'b0};
                        end
                        // Falling edge : sample MISO, count bit
                        else begin
                            rx_shift <= {rx_shift[6:0], SPI_MISO};
                            bit_cnt  <= bit_cnt + 1'b1;
                        end
                    end
                end

                default : ;   // DONE / others
            endcase
        end
    end

    // ---------------------------------------------------------
    // SCLK generation : toggles on every `clk_edge` in TRANSFER
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst)
            sclk_int <= 1'b0;          // CPOL = 0 -> idle low
        else if (state == TRANSFER && clk_edge)
            sclk_int <= ~sclk_int;
        else if (state == IDLE)
            sclk_int <= 1'b0;
    end

    // ---------------------------------------------------------
    // Outputs
    // ---------------------------------------------------------
    assign SPI_CLK = sclk_int;
    assign SPI_EN  = (state == IDLE) ? 1'b1 : 1'b0;  // active-low
    assign data_out = (state == DONE) ? rx_shift : data_out;

endmodule