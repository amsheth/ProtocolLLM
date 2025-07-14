//==============================================================
//  UART_driver.sv
//
//  Generic, full-duplex UART with
//      • Run-time selectable baud rate
//      • 8 data bits, optional parity, 2 stop bits
//      • Separate TX / RX state-machines
//      • Framing & parity error detection
//
//  Interface is exactly the one requested in the problem
//==============================================================

module UART_driver
#(
    //------------------------------------------------------------------
    //  GENERICS
    //------------------------------------------------------------------
    //  System clock frequency       (Hz)
    parameter int unsigned CLK_FREQ_HZ   = 50_000_000,
    //  Default baud-rate            (bit/s)
    parameter int unsigned BAUD_RATE     = 115_200,
    //  Oversampling (must be ≥ 3 ; 16 is common)
    parameter int unsigned OVERSAMPLE    = 16,
    //  Parity : 0 = none , 1 = even , 2 = odd
    parameter int unsigned PARITY_MODE   = 0
)
(
    //------------------------------------------------------------------
    //  PORTS
    //------------------------------------------------------------------
    input  logic        clk,            // System clock
    input  logic        rst,            // Asynchronous reset, active high

    //  TX interface
    input  logic        UART_Start,     // Pulse => send data_in
    input  logic [8:0]  data_in,        // 8 data bits, bit 8 ignored
    output logic        UART_Ready,     // High when TX idle
    output logic        UART_Busy,      // High while frame in progress
    output logic        TX,             // UART TX line

    //  RX interface
    input  logic        RX,             // UART RX line
    output logic [8:0]  data_out,       // Received byte, parity bit in [8]
    output logic        UART_Error      // Framing / parity error
);

    //------------------------------------------------------------------
    //  CONSTANTS
    //------------------------------------------------------------------
    localparam  int unsigned BAUD_DIV = CLK_FREQ_HZ / (BAUD_RATE * OVERSAMPLE); // clock cycles / oversample tick
    localparam  int unsigned BAUD_DIV_W = $clog2(BAUD_DIV);

    //------------------------------------------------------------------
    //  GLOBAL TICK:  OVERSAMPLE * BAUD_RATE  ticks / second
    //------------------------------------------------------------------
    logic [BAUD_DIV_W-1:0] baud_cnt;
    logic                  baud_tick;     // 1-cycle pulse every clk/(BAUD_RATE*OVERSAMPLE)

    always_ff @(posedge clk or posedge rst)
    begin
        if (rst) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_cnt == BAUD_DIV-1) begin
                baud_cnt  <= '0;
                baud_tick <= 1'b1;
            end else begin
                baud_cnt  <= baud_cnt + 1;
                baud_tick <= 1'b0;
            end
        end
    end

    //==============================================================
    //  TRANSMITTER
    //==============================================================
    typedef enum logic [2:0] {TX_IDLE, TX_START, TX_DATA, TX_PARITY, TX_STOP1, TX_STOP2} tx_state_t;
    tx_state_t  tx_state;

    logic [3:0] tx_bit_cnt;      // counts 0-7 data bits
    logic [7:0] tx_shift;        // shift register
    logic       tx_parity_bit;   // computed parity
    logic [3:0] tx_ovr_cnt;      // oversample counter within each bit
    logic       tx_line;         // registered TX line

    //  Parity computation helper
    function logic calc_parity( input logic [7:0] b );
        if (PARITY_MODE == 1)     // even
            calc_parity = ^b;     // even parity = XOR = 1 when #ones odd
        else                      // odd
            calc_parity = ~(^b);
    endfunction

    assign TX         = tx_line;
    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy  = ~UART_Ready;

    always_ff @(posedge clk or posedge rst)
    begin
        if (rst) begin
            tx_state     <= TX_IDLE;
            tx_bit_cnt   <= 0;
            tx_shift     <= '0;
            tx_parity_bit<= 1'b0;
            tx_ovr_cnt   <= 0;
            tx_line      <= 1'b1;       // idle level
        end
        else if (baud_tick) begin
            //------------------------------------------------------
            //  oversample counter – generates 1 bit-time every
            //  OVERSAMPLE baud ticks
            //------------------------------------------------------
            if (tx_state == TX_IDLE) begin
                tx_ovr_cnt <= 0;
            end else if (tx_ovr_cnt == (OVERSAMPLE-1)) begin
                tx_ovr_cnt <= 0;
            end else begin
                tx_ovr_cnt <= tx_ovr_cnt + 1;
            end

            //------------------------------------------------------
            //  Only change line once per full bit
            //------------------------------------------------------
            if ( (tx_state != TX_IDLE) && (tx_ovr_cnt != 0) )
                // not at the start of a new bit : keep output
                tx_line <= tx_line;
            else begin
                //--------------------------------------------------
                //  State machine
                //--------------------------------------------------
                unique case (tx_state)
                    //--------------------------------------------------
                    TX_IDLE : begin
                        tx_line <= 1'b1;               // idle high
                        if (UART_Start) begin
                            tx_shift      <= data_in[7:0];
                            tx_parity_bit <= (PARITY_MODE==0)? 1'b1 : calc_parity(data_in[7:0]);
                            tx_bit_cnt    <= 0;
                            tx_state      <= TX_START;
                        end
                    end
                    //--------------------------------------------------
                    TX_START : begin
                        tx_line  <= 1'b0;               // start bit
                        tx_state <= TX_DATA;
                    end
                    //--------------------------------------------------
                    TX_DATA : begin
                        tx_line <= tx_shift[0];
                        tx_shift<= {1'b0,tx_shift[7:1]};
                        if (tx_bit_cnt == 7) begin
                            tx_bit_cnt <= 0;
                            if (PARITY_MODE==0)
                                tx_state <= TX_STOP1;
                            else
                                tx_state <= TX_PARITY;
                        end else begin
                            tx_bit_cnt <= tx_bit_cnt + 1;
                        end
                    end
                    //--------------------------------------------------
                    TX_PARITY : begin
                        tx_line  <= tx_parity_bit;
                        tx_state <= TX_STOP1;
                    end
                    //--------------------------------------------------
                    TX_STOP1 : begin
                        tx_line  <= 1'b1;               // stop bit #1
                        tx_state <= TX_STOP2;
                    end
                    //--------------------------------------------------
                    TX_STOP2 : begin
                        tx_line  <= 1'b1;               // stop bit #2
                        tx_state <= TX_IDLE;
                    end
                endcase
            end // bit boundary
        end // baud_tick
    end // always_ff TX

    //==============================================================
    //  RECEIVER
    //==============================================================
    typedef enum logic [3:0]
    {
        RX_IDLE, RX_START, RX_DATA, RX_PARITY, RX_STOP1, RX_STOP2, RX_DONE, RX_ERROR
    } rx_state_t;

    rx_state_t  rx_state;
    logic [3:0] rx_bit_cnt;          // counts received data bits
    logic [7:0] rx_shift;
    logic [3:0] rx_ovr_cnt;          // samples within one bit
    logic [3:0] rx_mid_sample;       // middle of bit (OVERSAMPLE/2)
    logic       rx_samp;             // synchronised sample of RX pin
    logic       parity_calc;         // running parity
    logic       framing_err, parity_err;

    //  Middle sample tick : when ov_cnt == OVERSAMPLE/2
    assign rx_mid_sample = OVERSAMPLE >> 1;

    //  Simple metastability filter (double-register)
    logic rx_sync1, rx_sync2;
    always_ff @(posedge clk) begin
        rx_sync1 <= RX;
        rx_sync2 <= rx_sync1;
    end
    assign rx_samp = rx_sync2;

    //  Output registers
    always_ff @(posedge clk or posedge rst)
    begin
        if (rst) begin
            data_out    <= '0;
            UART_Error  <= 1'b0;
        end else if (rx_state == RX_DONE) begin
            data_out    <= {parity_calc, rx_shift}; // parity in bit[8]
            UART_Error  <= framing_err | parity_err;
        end
    end

    always_ff @(posedge clk or posedge rst)
    begin
        if (rst) begin
            rx_state      <= RX_IDLE;
            rx_bit_cnt    <= 0;
            rx_shift      <= '0;
            rx_ovr_cnt    <= 0;
            parity_calc   <= 1'b0;
            framing_err   <= 1'b0;
            parity_err    <= 1'b0;
        end
        else if (baud_tick) begin
            //------------------------------------------------------
            //  oversample counter
            //------------------------------------------------------
            if (rx_state == RX_IDLE)
                rx_ovr_cnt <= 0;
            else if (rx_ovr_cnt == (OVERSAMPLE-1))
                rx_ovr_cnt <= 0;
            else
                rx_ovr_cnt <= rx_ovr_cnt + 1;

            //------------------------------------------------------
            //  sample at middle of the bit
            //------------------------------------------------------
            logic sample_now;
            sample_now = (rx_ovr_cnt == rx_mid_sample);

            //------------------------------------------------------
            //  State machine
            //------------------------------------------------------
            unique case (rx_state)
                //--------------------------------------------------
                RX_IDLE : begin
                    framing_err <= 1'b0;
                    parity_err  <= 1'b0;
                    if (~rx_samp) begin          // start bit detected (line low)
                        rx_state   <= RX_START;
                        rx_ovr_cnt <= 0;
                    end
                end
                //--------------------------------------------------
                RX_START : begin
                    if (sample_now) begin
                        if (~rx_samp) begin      // confirm start bit still low
                            rx_bit_cnt  <= 0;
                            parity_calc <= 1'b0;
                            rx_state    <= RX_DATA;
                        end else begin           // false start
                            rx_state <= RX_ERROR;
                            framing_err <= 1'b1;
                        end
                    end
                end
                //--------------------------------------------------
                RX_DATA : begin
                    if (sample_now) begin
                        rx_shift <= {rx_samp, rx_shift[7:1]};
                        parity_calc <= parity_calc ^ rx_samp;
                        if (rx_bit_cnt == 7) begin
                            if (PARITY_MODE == 0)
                                rx_state <= RX_STOP1;
                            else
                                rx_state <= RX_PARITY;
                        end
                        rx_bit_cnt <= rx_bit_cnt + 1;
                    end
                end
                //--------------------------------------------------
                RX_PARITY : begin
                    if (sample_now) begin
                        //  Check even / odd
                        logic expected_parity;
                        expected_parity   = (PARITY_MODE==1) ? parity_calc : ~parity_calc;
                        parity_err        = (rx_samp != expected_parity);
                        rx_state          <= RX_STOP1;
                    end
                end
                //--------------------------------------------------
                RX_STOP1 : begin
                    if (sample_now) begin
                        if (~rx_samp) framing_err <= 1'b1;
                        rx_state <= RX_STOP2;
                    end
                end
                //--------------------------------------------------
                RX_STOP2 : begin
                    if (sample_now) begin
                        if (~rx_samp) framing_err <= 1'b1;
                        rx_state <= RX_DONE;
                    end
                end
                //--------------------------------------------------
                RX_DONE : begin
                    rx_state <= RX_IDLE;     // Data valid for 1 cycle
                end
                //--------------------------------------------------
                RX_ERROR : begin
                    rx_state <= RX_IDLE;     // resync
                end
            endcase
        end // baud_tick
    end // always_ff RX

endmodule