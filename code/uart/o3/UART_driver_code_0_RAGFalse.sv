//============================================================
//  UART_driver.sv
//
//  Full-duplex, 8-bit asynchronous UART controller
//  ‑ 1 start bit
//  ‑ 8 data bits (LSB first)
//  ‑ Optional parity (even / odd / none)
//  ‑ 1 stop bit
//  Parameterisable clock-rate, baud-rate and oversampling
//============================================================
`timescale 1ns/1ps
module UART_driver
#(
    // ------------------------------------------
    // User parameters
    // ------------------------------------------
    parameter longint  CLOCK_FREQ  = 50_000_000,  // Hz
    parameter longint  BAUD_RATE   = 115_200,     // bps
    parameter int      OVERSAMPLE  = 16,          // Must be power-of-2 ≥ 8
    parameter string   PARITY      = "NONE"       // "NONE","EVEN","ODD"
)
(
    input  logic       clk,         // System clock
    input  logic       rst,         // Asynchronous reset (active-high)

    // Transmit interface
    input  logic       UART_Start,  // Pulse to start TX of data_in
    input  logic [7:0] data_in,     // Byte to transmit
    output logic       UART_Ready,  // High when idle / ready
    output logic       UART_Busy,   // High while shifting a frame
    output logic       TX,          // UART TX line (idle = 1)

    // Receive interface
    input  logic       RX,          // UART RX line (idle = 1)
    output logic [7:0] data_out,    // Last correctly received byte
    output logic       UART_Error   // Parity or framing error flag
);

    // ---------------------------------------------------------
    //  Derived constants
    // ---------------------------------------------------------
    localparam longint BAUD_DIV     = CLOCK_FREQ / BAUD_RATE;              // TX bit-time divider
    localparam longint SAMPLE_DIV   = CLOCK_FREQ / (BAUD_RATE * OVERSAMPLE); // RX oversample divider

    localparam bit PARITY_EN  = (PARITY != "NONE");
    localparam bit PARITY_EVN = (PARITY == "EVEN");

    // ---------------------------------------------------------
    //  Baud-rate generator (shared)
    // ---------------------------------------------------------
    logic [31:0] baud_cnt;
    logic        baud_tick;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b0;
        end else if (baud_cnt == BAUD_DIV - 1) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 1;
            baud_tick <= 1'b0;
        end
    end

    // ---------------------------------------------------------
    //  TRANSMITTER
    // ---------------------------------------------------------
    localparam int EXTRA_BITS  = PARITY_EN ? 1 : 0;
    localparam int FRAME_BITS  = 1 /*start*/ + 8 /*data*/ + EXTRA_BITS + 1 /*stop*/;

    typedef enum logic [1:0] { TX_IDLE, TX_SHIFT } tx_state_t;
    tx_state_t            tx_state;
    logic [FRAME_BITS-1:0] tx_shift_reg;
    logic [$clog2(FRAME_BITS):0] tx_bit_cnt;

    // ready / busy flags
    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy  = (tx_state != TX_IDLE);

    // TX output register (idle high)
    assign TX = tx_shift_reg[0];

    // Build frame and start
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state      <= TX_IDLE;
            tx_shift_reg  <= {FRAME_BITS{1'b1}};
            tx_bit_cnt    <= '0;
        end else begin
            case (tx_state)
                //-------------------------------------------------
                TX_IDLE : begin
                    tx_shift_reg <= {FRAME_BITS{1'b1}}; // keep line high
                    if (UART_Start) begin
                        // Calculate parity when enabled
                        logic parity_bit;
                        if (PARITY_EN) begin
                            parity_bit = ^data_in;               // even parity by default
                            if (!PARITY_EVN) parity_bit = ~parity_bit; // odd parity
                        end
                        // Assemble frame (LSB first)
                        tx_shift_reg <= {
                            1'b1,                           // Stop bit (MSB shifted last)
                            (PARITY_EN ? parity_bit : 1'b1),// Parity (ignored if disabled)
                            data_in,                        // 8 data bits
                            1'b0                            // Start bit (LSB shifted first)
                        };
                        tx_bit_cnt   <= FRAME_BITS;
                        tx_state     <= TX_SHIFT;
                    end
                end
                //-------------------------------------------------
                TX_SHIFT : begin
                    if (baud_tick) begin
                        tx_shift_reg <= {1'b1, tx_shift_reg[FRAME_BITS-1:1]}; // logical right shift
                        if (tx_bit_cnt == 1) begin
                            tx_state <= TX_IDLE;
                        end
                        tx_bit_cnt <= tx_bit_cnt - 1;
                    end
                end
                //-------------------------------------------------
            endcase
        end
    end

    // ---------------------------------------------------------
    //  RECEIVER
    // ---------------------------------------------------------
    typedef enum logic [2:0] { RX_IDLE, RX_START, RX_DATA, RX_PARITY, RX_STOP } rx_state_t;
    rx_state_t      rx_state;

    logic [7:0]     rx_shift_reg;
    logic [3:0]     rx_bit_cnt;               // Counts 8 data bits
    logic [3:0]     os_cnt;                   // Oversample counter (0 .. OVERSAMPLE-1)
    logic [31:0]    sample_cnt;               // Divider counter -> sample_tick
    logic           sample_tick;              // Tick at the oversample rate
    logic           rx_parity_bit;
    logic           parity_err, framing_err;

    // -------------------------------------------------
    // Oversample clock (sample_tick)
    // -------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sample_cnt  <= '0;
            sample_tick <= 1'b0;
        end else if (sample_cnt == SAMPLE_DIV - 1) begin
            sample_cnt  <= '0;
            sample_tick <= 1'b1;
        end else begin
            sample_cnt  <= sample_cnt + 1;
            sample_tick <= 1'b0;
        end
    end

    // -------------------------------------------------
    // Receiver FSM
    // -------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state     <= RX_IDLE;
            os_cnt       <= '0;
            rx_bit_cnt   <= '0;
            rx_shift_reg <= '0;
            rx_parity_bit<= 1'b0;
            parity_err   <= 1'b0;
            framing_err  <= 1'b0;
            data_out     <= 8'h00;
        end else if (sample_tick) begin
            case (rx_state)
                //-------------------------------------------------
                RX_IDLE : begin
                    parity_err  <= 1'b0;
                    framing_err <= 1'b0;
                    if (!RX) begin              // Detect start bit (logic 0)
                        rx_state <= RX_START;
                        os_cnt   <= 0;
                    end
                end
                //-------------------------------------------------
                RX_START : begin
                    if (os_cnt == (OVERSAMPLE/2 - 1)) begin // Mid-bit sample
                        if (!RX) begin       // Validate start bit still low
                            rx_state <= RX_DATA;
                            os_cnt   <= 0;
                            rx_bit_cnt <= 0;
                        end else begin       // False start, go back idle
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        os_cnt <= os_cnt + 1;
                    end
                end
                //-------------------------------------------------
                RX_DATA : begin
                    if (os_cnt == OVERSAMPLE - 1) begin
                        os_cnt <= 0;
                        rx_shift_reg <= {RX, rx_shift_reg[7:1]}; // LSB first
                        rx_bit_cnt   <= rx_bit_cnt + 1;
                        if (rx_bit_cnt == 7) begin
                            if (PARITY_EN)
                                rx_state <= RX_PARITY;
                            else
                                rx_state <= RX_STOP;
                        end
                    end else begin
                        os_cnt <= os_cnt + 1;
                    end
                end
                //-------------------------------------------------
                RX_PARITY : begin
                    if (os_cnt == OVERSAMPLE - 1) begin
                        os_cnt <= 0;
                        rx_parity_bit <= RX;
                        // Check parity at the end of stop bit to avoid extra logic
                        rx_state <= RX_STOP;
                    end else begin
                        os_cnt <= os_cnt + 1;
                    end
                end
                //-------------------------------------------------
                RX_STOP : begin
                    if (os_cnt == OVERSAMPLE - 1) begin
                        os_cnt <= 0;
                        // Framing error if stop bit is not high
                        framing_err <= ~RX;
                        // Parity check
                        if (PARITY_EN) begin
                            logic calc_parity = ^rx_shift_reg;
                            if (!PARITY_EVN)  // ODD parity
                                calc_parity = ~calc_parity;
                            parity_err <= (calc_parity != rx_parity_bit);
                        end
                        // Latch received byte
                        if (!framing_err && !parity_err)
                            data_out <= rx_shift_reg;
                        rx_state <= RX_IDLE;
                    end else begin
                        os_cnt <= os_cnt + 1;
                    end
                end
                //-------------------------------------------------
            endcase
        end
    end

    // ---------------------------------------------------------
    //  Error flag output (sticky until next correctly received byte)
    // ---------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            UART_Error <= 1'b0;
        end else if (parity_err || framing_err) begin
            UART_Error <= 1'b1;
        end else if (rx_state == RX_IDLE && sample_tick && !parity_err && !framing_err) begin
            UART_Error <= 1'b0;  // Clear on good frame
        end
    end

endmodule