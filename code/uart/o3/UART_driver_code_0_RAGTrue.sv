/*****************************************************************************************
*  UART_driver – Full-duplex UART with configurable baud, parity and stop-bits
*
*  • 8-bit data, optional parity (even/odd), 1 or 2 stop bits
*  • Independent TX/RX finite-state-machines
*  • Single baud-rate generator shared by both directions
*
*  Notes
*  -----
*  1. `CLK_FREQ` and `BAUD_RATE` **must** be chosen such that  
*        CLK_FREQ / BAUD_RATE / OVERSAMPLE  ≥ 1   and is an integer.
*
*  2. RX path uses 16× oversampling and samples incoming bits in the centre
*     of each bit-period (8th tick of the 16).  
*     TX path shifts on the first tick of each bit.
*
******************************************************************************************/
module UART_driver #(
    // ------------------------------------------------------------------
    // USER CONFIGURABLE GENERICS
    // ------------------------------------------------------------------
    parameter int CLK_FREQ    = 50_000_000,  // System clock  (Hz)
    parameter int BAUD_RATE   = 115_200,     // Desired baud  (bps)
    parameter bit PARITY_EN   = 0,           // 0 – none , 1 – parity on
    parameter bit PARITY_EVEN = 1,           // 1 – even , 0 – odd   (if enabled)
    parameter int STOP_BITS   = 1            // 1 or 2 stop bits
) (
    // ------------------------------------------------------------------
    // PORTS
    // ------------------------------------------------------------------
    input  logic       clk,            // System clock
    input  logic       rst,            // Asynchronous reset – active high
    // TX interface
    input  logic       UART_Start,     // Pulse to start TX of data_in
    input  logic [7:0] data_in,        // Data to transmit
    output logic       UART_Ready,     // 1 = ready/idle
    output logic       UART_Busy,      // 1 = currently transmitting
    output logic       TX,             // UART Tx line
    // RX interface
    input  logic       RX,             // UART Rx line
    output logic [7:0] data_out,       // Most recently received byte
    output logic       UART_Error      // 1 = frame/parity error detected
);

    // ------------------------------------------------------------------
    // CONSTANTS
    // ------------------------------------------------------------------
    localparam int OVERSAMPLE  = 16;                           // RX oversampling factor
    localparam int BAUD_DIV    = CLK_FREQ / BAUD_RATE;         // 1× baud tick divider
    localparam int SAMPLE_DIV  = BAUD_DIV / OVERSAMPLE;        // 16× tick divider

    // ------------------------------------------------------------------
    // SHARED BAUD GENERATOR (1× tick and 16× tick)
    // ------------------------------------------------------------------
    logic [31:0] baud_cnt, sample_cnt;
    logic        baud_tick, sample_tick;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt   <= 0;
            sample_cnt <= 0;
            baud_tick  <= 0;
            sample_tick<= 0;
        end else begin
            // --- 1× baud tick (for TX) -------------------------------
            if (baud_cnt == BAUD_DIV-1) begin
                baud_cnt  <= 0;
                baud_tick <= 1;
            end else begin
                baud_cnt  <= baud_cnt + 1;
                baud_tick <= 0;
            end
            // --- 16× tick (for RX oversampling) ----------------------
            if (sample_cnt == SAMPLE_DIV-1) begin
                sample_cnt  <= 0;
                sample_tick <= 1;
            end else begin
                sample_cnt  <= sample_cnt + 1;
                sample_tick <= 0;
            end
        end
    end

    // ------------------------------------------------------------------
    // TRANSMITTER
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {TX_IDLE, TX_START, TX_DATA, TX_PAR, TX_STOP} tx_state_t;
    tx_state_t tx_state;

    logic [2:0]     bit_idx;     // Counts data bits
    logic [7:0]     tx_shift;
    logic [1:0]     stop_cnt;    // 1 or 2 stop bits

    // next parity calculation
    function automatic logic parity_bit (input logic [7:0] d);
        logic p;
        begin
            p = ^d;                               // XOR reduction
            if (PARITY_EVEN == 1) parity_bit = p; // even parity
            else                  parity_bit = ~p; // odd parity
        end
    endfunction

    // TX FSM -----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state   <= TX_IDLE;
            TX         <= 1'b1;       // idle line high
            UART_Ready <= 1'b1;
            UART_Busy  <= 1'b0;
            bit_idx    <= 3'd0;
            stop_cnt   <= 2'd0;
            tx_shift   <= 8'h00;
        end else begin
            if (baud_tick) begin
                case (tx_state)
                    TX_IDLE: begin
                        if (UART_Start) begin
                            UART_Ready <= 1'b0;
                            UART_Busy  <= 1'b1;
                            tx_shift   <= data_in;
                            bit_idx    <= 3'd0;
                            TX         <= 1'b0;   // start bit
                            tx_state   <= TX_START;
                        end
                    end

                    TX_START: begin
                        TX       <= tx_shift[0];  // first data bit
                        tx_shift <= {1'b0, tx_shift[7:1]};
                        bit_idx  <= 3'd1;
                        tx_state <= TX_DATA;
                    end

                    TX_DATA: begin
                        if (bit_idx != 3'd7) begin
                            TX       <= tx_shift[0];
                            tx_shift <= {1'b0, tx_shift[7:1]};
                            bit_idx  <= bit_idx + 1;
                        end else begin
                            // Last data bit sent this cycle
                            if (PARITY_EN) begin
                                TX       <= parity_bit(data_in);
                                tx_state <= TX_PAR;
                            end else begin
                                TX       <= 1'b1;   // stop bit
                                stop_cnt <= STOP_BITS-1;
                                tx_state <= TX_STOP;
                            end
                        end
                    end

                    TX_PAR: begin
                        TX       <= 1'b1;          // first stop bit
                        stop_cnt <= STOP_BITS-1;
                        tx_state <= TX_STOP;
                    end

                    TX_STOP: begin
                        if (stop_cnt != 0) begin
                            stop_cnt <= stop_cnt - 1;
                            TX       <= 1'b1;
                        end else begin
                            UART_Ready <= 1'b1;
                            UART_Busy  <= 1'b0;
                            tx_state   <= TX_IDLE;
                            TX         <= 1'b1;
                        end
                    end
                    default: tx_state <= TX_IDLE;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // RECEIVER
    // ------------------------------------------------------------------
    typedef enum logic [2:0] {RX_IDLE, RX_START, RX_DATA, RX_PAR, RX_STOP} rx_state_t;
    rx_state_t rx_state;

    logic [3:0] sample_ctr;   // 0..15
    logic [2:0] rx_bit_idx;
    logic [7:0] rx_shift;
    logic       calc_parity, rx_parity;
    logic       frame_err, parity_err;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state     <= RX_IDLE;
            sample_ctr   <= 4'd0;
            rx_bit_idx   <= 3'd0;
            rx_shift     <= 8'h00;
            data_out     <= 8'h00;
            UART_Error   <= 1'b0;
        end else begin
            UART_Error <= frame_err | parity_err;  // sticky until next good frame

            if (sample_tick) begin
                case (rx_state)
                    //--------------------------------------------------
                    RX_IDLE: begin
                        frame_err   <= 1'b0;
                        parity_err  <= 1'b0;
                        if (RX == 1'b0) begin        // start bit detected
                            rx_state   <= RX_START;
                            sample_ctr <= 4'd0;
                        end
                    end
                    //--------------------------------------------------
                    RX_START: begin
                        if (sample_ctr == 4'd7) begin // mid of start bit
                            if (RX == 1'b0) begin     // valid start
                                sample_ctr <= 4'd0;
                                rx_bit_idx <= 3'd0;
                                rx_state   <= RX_DATA;
                            end else begin            // false start
                                rx_state <= RX_IDLE;
                            end
                        end else begin
                            sample_ctr <= sample_ctr + 1;
                        end
                    end
                    //--------------------------------------------------
                    RX_DATA: begin
                        if (sample_ctr == OVERSAMPLE-1) begin
                            sample_ctr      <= 4'd0;
                            rx_shift[rx_bit_idx] <= RX; // sample in middle
                            if (rx_bit_idx == 3'd7) begin
                                if (PARITY_EN) begin
                                    rx_state <= RX_PAR;
                                end else begin
                                    rx_state <= RX_STOP;
                                end
                            end
                            rx_bit_idx <= rx_bit_idx + 1;
                        end else begin
                            sample_ctr <= sample_ctr + 1;
                        end
                    end
                    //--------------------------------------------------
                    RX_PAR: begin
                        if (sample_ctr == OVERSAMPLE-1) begin
                            sample_ctr  <= 4'd0;
                            rx_parity   <= RX;
                            // compute parity
                            calc_parity <= parity_bit(rx_shift);
                            parity_err  <= (rx_parity != calc_parity);
                            rx_state    <= RX_STOP;
                        end else begin
                            sample_ctr <= sample_ctr + 1;
                        end
                    end
                    //--------------------------------------------------
                    RX_STOP: begin
                        if (sample_ctr == OVERSAMPLE-1) begin
                            sample_ctr <= 4'd0;
                            if (RX != 1'b1) frame_err <= 1'b1; // stop bit must be high
                            if (STOP_BITS == 2) begin
                                // wait one more stop bit
                                if (RX != 1'b1) frame_err <= 1'b1;
                            end
                            data_out <= rx_shift;
                            rx_state <= RX_IDLE;
                        end else begin
                            sample_ctr <= sample_ctr + 1;
                        end
                    end
                    default: rx_state <= RX_IDLE;
                endcase
            end
        end
    end
endmodule