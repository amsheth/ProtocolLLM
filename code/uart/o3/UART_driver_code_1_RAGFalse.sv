// -----------------------------------------------------------------------------
// Universal Asynchronous Receiver / Transmitter (UART) – full-duplex
//  • 8 data bits
//  • optional parity bit (even / odd)
//  • 2 stop bits
//  • parameterised baud-rate
//
// Interface -------------------------------------------------------------------
//   clk         : System clock
//   rst         : Asynchronous reset (active-high)
//   UART_Start  : Pulse-high to start a transmission of data_in
//   data_in [8] :  {parity , 8-bit data}   – parity bit is ignored when
//                  PARITY_ENABLE = 0.  LSB is the first bit sent on the line
//   RX          : Serial data from external device
//   TX          : Serial data to   external device
//   data_out[8] : {parity , 8-bit data} captured after a complete frame
//   UART_Ready  : High when transmitter can accept a new byte
//   UART_Busy   : High while a byte is being transmitted
//   UART_Error  : One-clock-cycle-wide pulse on framing or parity error
// -----------------------------------------------------------------------------
module UART_driver #(
    parameter int CLOCK_FREQ     = 50_000_000,      // Hz
    parameter int BAUD_RATE      =     115_200,     // bps
    parameter bit PARITY_ENABLE  = 1'b1,            // 1 = parity bit present
    parameter bit PARITY_EVEN    = 1'b1             // 1 = even, 0 = odd
)(
    input  logic        clk,
    input  logic        rst,

    // transmitter side
    input  logic        UART_Start,
    input  logic [8:0]  data_in,          // {parity,data[7:0]}

    // receiver side
    input  logic        RX,

    // outputs
    output logic        TX,
    output logic [8:0]  data_out,         // {parity,data[7:0]}
    output logic        UART_Ready,
    output logic        UART_Busy,
    output logic        UART_Error
);

    //--------------------------------------------------------------------------
    //  Common baud-tick generator
    //--------------------------------------------------------------------------
    localparam int BAUD_DIV = CLOCK_FREQ / BAUD_RATE;        // ≥1
    localparam int CNT_W    = $clog2(BAUD_DIV);

    logic [CNT_W-1:0] baud_cnt;
    logic             baud_tick;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b0;
        end
        else if (baud_cnt == BAUD_DIV-1) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b1;
        end
        else begin
            baud_cnt  <= baud_cnt + 1'b1;
            baud_tick <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    //  TRANSMITTER
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] { TX_IDLE, TX_START, TX_DATA,
                               TX_PARITY, TX_STOP1, TX_STOP2 } tx_state_t;

    tx_state_t   tx_state;
    logic [3:0]  tx_bit_idx;        // counts data bits (0-7)
    logic [8:0]  tx_shift;          // {parity/data}
    logic        calc_parity;

    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy  = ~UART_Ready;

    // generate TX line
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state    <= TX_IDLE;
            tx_shift    <= '0;
            tx_bit_idx  <= '0;
            calc_parity <= 1'b0;
            TX          <= 1'b1;            // line is high when idle
        end
        else begin
            if (tx_state == TX_IDLE) begin
                TX <= 1'b1;                 // keep line high
                if (UART_Start) begin
                    // load data and advance to START
                    tx_shift[7:0] <= data_in[7:0];
                    if (PARITY_ENABLE) begin
                        // compute parity on 8 data bits
                        calc_parity        <= ^data_in[7:0] ^ PARITY_EVEN; // even/odd
                        tx_shift[8]        <= '0;   // placeholder
                    end
                    tx_bit_idx  <= 4'd0;
                    tx_state    <= TX_START;
                end
            end

            else if (baud_tick) begin
                unique case (tx_state)

                    TX_START: begin
                        TX       <= 1'b0;                       // start bit
                        tx_state <= TX_DATA;
                    end

                    TX_DATA: begin
                        TX <= tx_shift[tx_bit_idx];             // LSB first
                        if (tx_bit_idx == 4'd7) begin
                            tx_state <= PARITY_ENABLE ? TX_PARITY : TX_STOP1;
                        end
                        tx_bit_idx <= tx_bit_idx + 1'b1;
                    end

                    TX_PARITY: begin
                        TX       <= calc_parity;
                        tx_state <= TX_STOP1;
                    end

                    TX_STOP1: begin
                        TX       <= 1'b1;
                        tx_state <= TX_STOP2;
                    end

                    TX_STOP2: begin
                        TX       <= 1'b1;
                        tx_state <= TX_IDLE;
                    end

                    default: tx_state <= TX_IDLE;
                endcase
            end
        end
    end

    //--------------------------------------------------------------------------
    //  RECEIVER
    //--------------------------------------------------------------------------
    typedef enum logic [2:0] { RX_IDLE, RX_START, RX_DATA,
                               RX_PARITY, RX_STOP1, RX_STOP2 } rx_state_t;

    rx_state_t  rx_state;
    logic [3:0] rx_bit_idx;
    logic [7:0] rx_shift;
    logic       rx_parity_bit;
    logic       sample_tick;                    // tick centred in bit time
    logic [CNT_W-1:0] bit_cnt;                  // local counter for centring

    // centering counter : generate sample_tick in the middle of each bit
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt     <= '0;
            sample_tick <= 1'b0;
        end
        else begin
            sample_tick <= 1'b0;
            if (rx_state == RX_IDLE) begin
                bit_cnt <= BAUD_DIV/2;          // vigilantly centre first sample
            end
            else if (bit_cnt == BAUD_DIV-1) begin
                bit_cnt     <= '0';
                sample_tick <= 1'b1;            // strobe to grab RX
            end
            else begin
                bit_cnt <= bit_cnt + 1'b1;
            end
        end
    end

    // main receiver FSM
    logic framing_error, parity_error;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state      <= RX_IDLE;
            rx_bit_idx    <= '0;
            rx_shift      <= '0;
            rx_parity_bit <= 1'b0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
            data_out      <= '0;
            UART_Error    <= 1'b0;
        end
        else begin
            UART_Error <= 1'b0;                // default – pulse only on error

            case (rx_state)

                RX_IDLE: begin
                    if (~RX) begin              // detect start bit (falling edge)
                        rx_state   <= RX_START;
                        bit_cnt    <= BAUD_DIV/2;  // already started; recalc
                    end
                end

                RX_START: if (sample_tick) begin
                    if (~RX) begin              // still low? valid start
                        rx_bit_idx <= 4'd0;
                        rx_state   <= RX_DATA;
                    end
                    else begin                  // false start
                        rx_state <= RX_IDLE;
                    end
                end

                RX_DATA: if (sample_tick) begin
                    rx_shift[rx_bit_idx] <= RX; // LSB first
                    if (rx_bit_idx == 4'd7) begin
                        rx_state <= PARITY_ENABLE ? RX_PARITY : RX_STOP1;
                    end
                    rx_bit_idx <= rx_bit_idx + 1'b1;
                end

                RX_PARITY: if (sample_tick) begin
                    rx_parity_bit <= RX;
                    rx_state      <= RX_STOP1;
                end

                RX_STOP1: if (sample_tick) begin
                    if (RX) begin
                        rx_state <= RX_STOP2;
                    end
                    else begin
                        framing_error <= 1'b1;
                        rx_state      <= RX_IDLE;
                    end
                end

                RX_STOP2: if (sample_tick) begin
                    if (RX) begin
                        // frame finished – check parity & output byte
                        if (PARITY_ENABLE) begin
                            parity_error <= (rx_parity_bit ^
                                             (^rx_shift) ^
                                             PARITY_EVEN);
                        end
                        else parity_error <= 1'b0;

                        data_out <= {rx_parity_bit, rx_shift};

                        if (framing_error | parity_error) begin
                            UART_Error <= 1'b1;
                        end
                    end
                    else framing_error <= 1'b1;

                    // Go back idle for next byte
                    rx_state       <= RX_IDLE;
                    framing_error  <= 1'b0;
                    parity_error   <= 1'b0;
                end

                default: rx_state <= RX_IDLE;

            endcase
        end
    end

endmodule