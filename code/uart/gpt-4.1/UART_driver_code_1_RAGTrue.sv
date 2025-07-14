module UART_driver (
    input  logic        clk,         // System clock
    input  logic        rst,         // Asynchronous reset (active high)
    input  logic        UART_Start,  // Initiate transmission (1-pulse)
    input  logic [8:0]  data_in,     // {parity_enabled, [7:0]data}
    input  logic        RX,          // UART receive line
    output logic        TX,          // UART transmit line
    output logic [8:0]  data_out,    // {parity_error_or_en[8], [7:0]received data}
    output logic        UART_Ready,  // Ready for next transmit
    output logic        UART_Busy,   // Currently transmitting
    output logic        UART_Error   // High if framing/parity error
);

    // Baud rate config (default for 115200bps @ 50MHz: 434)
    parameter integer BAUD_DIVISOR = 434; // Set to your target clock/baud
    parameter         N_DATA       = 8;
    parameter         USE_PARITY   = 1;   // 1=enable parity support

    // -------------------------
    // Baud rate generator
    // -------------------------
    logic [15:0] baud_cnt, baud_cnt_rx;
    logic        baud_tick, baud_tick_rx;

    // TX generator
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt <= 0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_cnt == BAUD_DIVISOR-1) begin
                baud_cnt <= 0;
                baud_tick <= 1'b1;
            end else begin
                baud_cnt <= baud_cnt + 1;
                baud_tick <= 1'b0;
            end
        end
    end

    // RX generator (oversample by 4)
    localparam RX_OVERSAMPLE = 4;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt_rx <= 0;
            baud_tick_rx <= 1'b0;
        end else begin
            if (baud_cnt_rx == (BAUD_DIVISOR/RX_OVERSAMPLE)-1) begin
                baud_cnt_rx <= 0;
                baud_tick_rx <= 1'b1;
            end else begin
                baud_cnt_rx <= baud_cnt_rx + 1;
                baud_tick_rx <= 1'b0;
            end
        end
    end

    // ----------------------------------------
    // UART Transmitter
    // ----------------------------------------
    typedef enum logic[2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP1,
        TX_STOP2
    } tx_state_t;
    tx_state_t tx_state;

    logic [N_DATA-1:0] tx_data_reg;
    logic        tx_parity_en;
    logic        tx_parity_bit;
    logic [3:0]  tx_cnt;
    logic        tx_fifo_ready;

    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy  = (tx_state != TX_IDLE);

    // Compute parity if needed
    function logic compute_parity(input logic [N_DATA-1:0] dat);
        return ^dat; // even parity
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state      <= TX_IDLE;
            tx_data_reg   <= '0;
            tx_parity_en  <= 1'b0;
            tx_parity_bit <= 1'b0;
            tx_cnt        <= 0;
            TX            <= 1'b1;
        end else begin
            baud_tick: if (baud_tick) begin
                case (tx_state)
                    TX_IDLE: begin
                        TX <= 1'b1;
                        if (UART_Start) begin
                            tx_parity_en  <= data_in[8];
                            tx_data_reg   <= data_in[7:0];
                            tx_parity_bit <= compute_parity(data_in[7:0]);
                            tx_cnt        <= 0;
                            tx_state      <= TX_START;
                        end
                    end
                    TX_START: begin
                        TX <= 1'b0;           // Start bit
                        tx_state <= TX_DATA;
                    end
                    TX_DATA: begin
                        TX <= tx_data_reg[tx_cnt];
                        if (tx_cnt == N_DATA-1)
                            tx_state <= (tx_parity_en && USE_PARITY) ? TX_PARITY : TX_STOP1;
                        tx_cnt <= tx_cnt + 1;
                    end
                    TX_PARITY: begin
                        TX <= tx_parity_bit;
                        tx_state <= TX_STOP1;
                    end
                    TX_STOP1: begin
                        TX <= 1'b1;           // Stop bit 1
                        tx_state <= TX_STOP2;
                    end
                    TX_STOP2: begin
                        TX <= 1'b1;           // Stop bit 2
                        tx_state <= TX_IDLE;
                    end
                    default: tx_state <= TX_IDLE;
                endcase
            end
        end
    end

    // ----------------------------------------
    // UART Receiver
    // ----------------------------------------
    typedef enum logic[2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP1,
        RX_STOP2
    } rx_state_t;
    rx_state_t rx_state;

    logic [N_DATA-1:0] rx_shift;
    logic [3:0]  rx_cnt;
    logic        rx_sampled;
    logic        rx_parity_en;
    logic        rx_parity_ok, rx_parity_bit, rx_parity_r;
    logic        rx_fr_err, rx_parity_err;
    logic        rx_busy_i;
    logic        rx_start_det;
    logic [1:0]  rx_bit_sample_cntr; // oversample for noise immunity

    // Majority sampler for start bit
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state     <= RX_IDLE;
            rx_cnt       <= 0;
            rx_shift     <= 0;
            rx_parity_en <= 0;
            data_out     <= 0;
            UART_Error   <= 1'b0;
        end else begin
            baud_tick_rx: if (baud_tick_rx) begin
                case(rx_state)
                RX_IDLE: begin
                    UART_Error <= 1'b0;
                    if (~RX) begin // Detected start bit
                        rx_state   <= RX_START;
                        rx_cnt     <= 0;
                        rx_bit_sample_cntr <= 0;
                    end
                end
                RX_START: begin
                    rx_bit_sample_cntr <= rx_bit_sample_cntr + 1;
                    // Sample at the mid-point to reduce metastability and noise
                    if (rx_bit_sample_cntr == (RX_OVERSAMPLE/2-1)) begin
                        if (~RX) begin
                            rx_state <= RX_DATA;
                            rx_cnt   <= 0;
                        end else begin
                            rx_state <= RX_IDLE; // False start bit
                        end
                    end
                end
                RX_DATA: begin
                    rx_shift[rx_cnt] <= RX;
                    if (rx_cnt == N_DATA-1)
                        rx_state <= (USE_PARITY) ? RX_PARITY : RX_STOP1;
                    rx_cnt <= rx_cnt + 1;
                end
                RX_PARITY: begin
                    rx_parity_bit <= RX;
                    rx_state <= RX_STOP1;
                end
                RX_STOP1: begin
                    if (~RX) begin
                        UART_Error <= 1'b1; // Framing error (stop bit should be '1')
                    end
                    rx_state <= RX_STOP2;
                end
                RX_STOP2: begin
                    if (~RX) begin
                        UART_Error <= 1'b1;
                    end
                    // Output data, check parity
                    rx_parity_en = USE_PARITY;
                    rx_parity_r  = compute_parity(rx_shift);
                    rx_parity_ok = (USE_PARITY) ? (rx_parity_bit == rx_parity_r) : 1'b1;
                    rx_parity_err = (USE_PARITY) ? ~(rx_parity_ok) : 1'b0;
                    data_out <= {rx_parity_err, rx_shift};
                    UART_Error <= rx_parity_err;
                    rx_state <= RX_IDLE;
                end
                default: rx_state <= RX_IDLE;
                endcase
            end
        end
    end

endmodule