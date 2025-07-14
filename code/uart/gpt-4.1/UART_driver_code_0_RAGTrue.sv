module UART_driver #(
    parameter CLK_FREQ = 50000000,      // System clock frequency
    parameter BAUD_RATE = 115200,       // Baud rate (configurable)
    parameter PARITY_ENABLE = 0,        // 0: no parity, 1: even parity, 2: odd parity
    parameter PARITY_ODD = 1            // 1: odd parity, 0: even (only if PARITY_ENABLE != 0)
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       UART_Start,
    input  logic [7:0] data_in,
    input  logic       RX,
    output logic       TX,
    output logic [7:0] data_out,
    output logic       UART_Ready,
    output logic       UART_Busy,
    output logic       UART_Error
);

    // Baud generator
    localparam integer BAUD_DIV = CLK_FREQ/(BAUD_RATE);
    logic [$clog2(BAUD_DIV)-1:0] baud_cnt;
    logic baud_tick;

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            baud_cnt <= 0;
            baud_tick <= 0;
        end else begin
            if (baud_cnt == 0) begin
                baud_cnt <= BAUD_DIV-1;
                baud_tick <= 1;
            end else begin
                baud_cnt <= baud_cnt - 1;
                baud_tick <= 0;
            end
        end
    end

    // FSM States
    typedef enum logic [2:0] {
        IDLE, START, DATA, PARITY, STOP
    } tx_state_t, rx_state_t;

    // Transmit signals
    tx_state_t      tx_state, tx_state_nxt;
    logic [3:0]     tx_bit_cnt, tx_bit_cnt_nxt;
    logic [7:0]     tx_data_buf, tx_data_buf_nxt;
    logic           tx_parity_bit, tx_parity_bit_nxt;
    logic [7:0]     tx_data_latch;
    logic           tx_line, tx_line_nxt;
    logic           tx_busy, tx_busy_nxt;
    logic           tx_ready, tx_ready_nxt;

    // TX FSM logic
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            tx_state     <= IDLE;
            tx_bit_cnt   <= 0;
            tx_data_buf  <= 8'h00;
            tx_parity_bit<= 0;
            TX           <= 1;
            UART_Busy    <= 0;
            UART_Ready   <= 1;
        end else if(baud_tick) begin
            tx_state     <= tx_state_nxt;
            tx_bit_cnt   <= tx_bit_cnt_nxt;
            tx_data_buf  <= tx_data_buf_nxt;
            tx_parity_bit<= tx_parity_bit_nxt;
            TX           <= tx_line_nxt;
            UART_Busy    <= tx_busy_nxt;
            UART_Ready   <= tx_ready_nxt;
        end
    end

    always_comb begin
        // Default assignments
        tx_state_nxt     = tx_state;
        tx_bit_cnt_nxt   = tx_bit_cnt;
        tx_data_buf_nxt  = tx_data_buf;
        tx_parity_bit_nxt= tx_parity_bit;
        tx_line_nxt      = TX;
        tx_busy_nxt      = UART_Busy;
        tx_ready_nxt     = UART_Ready;

        case(tx_state)
            IDLE: begin
                tx_line_nxt  = 1;
                tx_busy_nxt  = 0;
                tx_ready_nxt = 1;
                if(UART_Start) begin
                    tx_state_nxt    = START;
                    tx_data_buf_nxt = data_in;
                    tx_parity_bit_nxt = (PARITY_ENABLE==0) ? 0 : ^data_in ^ (PARITY_ENABLE==2 ? 1'b1 : 1'b0);
                    tx_bit_cnt_nxt  = 0;
                    tx_line_nxt     = 0; // Start bit
                    tx_busy_nxt     = 1;
                    tx_ready_nxt    = 0;
                end
            end
            START: begin
                tx_line_nxt = 0;
                tx_state_nxt = DATA;
            end
            DATA: begin
                tx_line_nxt = tx_data_buf[tx_bit_cnt];
                if(tx_bit_cnt == 7) begin
                    if(PARITY_ENABLE != 0)
                        tx_state_nxt = PARITY;
                    else
                        tx_state_nxt = STOP;
                end
                tx_bit_cnt_nxt = tx_bit_cnt + 1'b1;
            end
            PARITY: begin
                tx_line_nxt = tx_parity_bit;
                tx_state_nxt = STOP;
            end
            STOP: begin
                tx_line_nxt = 1;
                tx_state_nxt = IDLE;
                tx_ready_nxt = 1;
                tx_busy_nxt = 0;
            end
        endcase
    end

    // Receive signals
    rx_state_t      rx_state, rx_state_nxt;
    logic [3:0]     rx_bit_cnt, rx_bit_cnt_nxt;
    logic [7:0]     rx_data_buf, rx_data_buf_nxt;
    logic           rx_sampled, rx_sampled_nxt;
    logic           rx_parity_bit, rx_parity_bit_nxt;
    logic           rx_error, rx_error_nxt;
    logic [7:0]     rx_data_out, rx_data_out_nxt;
    logic           rx_busy, rx_busy_nxt;

    // RX sampler (sample in center of bit)
    localparam integer RX_DIV = BAUD_DIV/2;
    logic [$clog2(RX_DIV):0] rx_sample_cnt;
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            rx_sample_cnt <= 0;
        end else if (rx_state == IDLE && RX == 0) begin
            rx_sample_cnt <= RX_DIV;
        end else if (rx_state != IDLE && baud_tick) begin
            rx_sample_cnt <= RX_DIV;
        end
    end

    // RX FSM logic
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            rx_state      <= IDLE;
            rx_bit_cnt    <= 0;
            rx_data_buf   <= 8'h00;
            UART_Error    <= 0;
            data_out      <= 8'h00;
            rx_busy       <= 0;
        end else if (baud_tick) begin
            rx_state      <= rx_state_nxt;
            rx_bit_cnt    <= rx_bit_cnt_nxt;
            rx_data_buf   <= rx_data_buf_nxt;
            UART_Error    <= rx_error_nxt;
            data_out      <= rx_data_out_nxt;
            rx_busy       <= rx_busy_nxt;
        end
    end

    always_comb begin
        rx_state_nxt    = rx_state;
        rx_bit_cnt_nxt  = rx_bit_cnt;
        rx_data_buf_nxt = rx_data_buf;
        rx_parity_bit_nxt= rx_parity_bit;
        rx_error_nxt    = 0;
        rx_data_out_nxt = data_out;
        rx_busy_nxt     = rx_busy;
        case(rx_state)
            IDLE: begin
                rx_busy_nxt = 0;
                if(RX==0) begin // start bit detected
                    rx_state_nxt = START;
                    rx_bit_cnt_nxt = 0;
                end
            end
            START: begin
                if(RX==0) begin // valid start bit
                    rx_state_nxt = DATA;
                    rx_busy_nxt = 1;
                end else begin // false start bit (line went high)
                    rx_state_nxt = IDLE;
                end
            end
            DATA: begin
                rx_data_buf_nxt[rx_bit_cnt] = RX;
                if(rx_bit_cnt == 7) begin
                    if(PARITY_ENABLE != 0)
                        rx_state_nxt = PARITY;
                    else
                        rx_state_nxt = STOP;
                end
                rx_bit_cnt_nxt = rx_bit_cnt + 1'b1;
            end
            PARITY: begin
                rx_parity_bit_nxt = RX;
                if ((PARITY_ENABLE==1 && (^(rx_data_buf_nxt)^rx_parity_bit_nxt)) ||
                    (PARITY_ENABLE==2 && (~(^(rx_data_buf_nxt)^rx_parity_bit_nxt)))) begin
                    rx_error_nxt = 1; // Parity Error
                end
                rx_state_nxt = STOP;
            end
            STOP: begin
                if(RX != 1'b1) begin
                    rx_error_nxt = 1; // Framing Error
                end else begin
                    rx_data_out_nxt = rx_data_buf_nxt;
                end
                rx_state_nxt = IDLE;
                rx_busy_nxt = 0;
            end
        endcase
    end

endmodule