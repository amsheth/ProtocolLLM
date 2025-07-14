module UART_driver #(
    parameter BAUD_RATE = 115200,      // Default baud rate
    parameter CLOCK_FREQ = 50000000,   // System clock frequency
    parameter PARITY_EN = 0,           // 0: No parity, 1: Even parity, 2: Odd parity
    parameter PARITY_TYPE = 0          // 0: Even, 1: Odd (used if PARITY_EN != 0)
)(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Baud rate generator
    localparam integer BAUD_DIV = CLOCK_FREQ / BAUD_RATE;
    logic [$clog2(BAUD_DIV)-1:0] baud_cnt;
    logic baud_tick;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt <= 0;
            baud_tick <= 0;
        end else if (baud_cnt == BAUD_DIV-1) begin
            baud_cnt <= 0;
            baud_tick <= 1;
        end else begin
            baud_cnt <= baud_cnt + 1;
            baud_tick <= 0;
        end
    end

    // Transmitter
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP
    } tx_state_t;

    tx_state_t tx_state;
    logic [3:0] tx_bit_cnt;
    logic [7:0] tx_shift_reg;
    logic       tx_parity_bit;
    logic       tx_busy;
    logic       tx_ready;
    logic       tx_line;

    assign TX = tx_line;
    assign UART_Busy = tx_busy;
    assign UART_Ready = tx_ready;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state      <= TX_IDLE;
            tx_bit_cnt    <= 0;
            tx_shift_reg  <= 0;
            tx_parity_bit <= 0;
            tx_busy       <= 0;
            tx_ready      <= 1;
            tx_line       <= 1; // Idle is high
        end else begin
            if (tx_state == TX_IDLE) begin
                tx_line  <= 1;
                tx_busy  <= 0;
                tx_ready <= 1;
                if (UART_Start) begin
                    tx_shift_reg  <= data_in;
                    tx_bit_cnt    <= 0;
                    tx_busy       <= 1;
                    tx_ready      <= 0;
                    // Parity calculation
                    if (PARITY_EN != 0) begin
                        tx_parity_bit <= ^data_in; // Even parity by default
                        if (PARITY_TYPE == 1)
                            tx_parity_bit <= ~tx_parity_bit; // Odd parity
                    end
                    tx_state <= TX_START;
                end
            end else if (baud_tick) begin
                case (tx_state)
                    TX_START: begin
                        tx_line <= 0; // Start bit
                        tx_state <= TX_DATA;
                        tx_bit_cnt <= 0;
                    end
                    TX_DATA: begin
                        tx_line <= tx_shift_reg[0];
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        tx_bit_cnt <= tx_bit_cnt + 1;
                        if (tx_bit_cnt == 7) begin
                            if (PARITY_EN != 0)
                                tx_state <= TX_PARITY;
                            else
                                tx_state <= TX_STOP;
                        end
                    end
                    TX_PARITY: begin
                        tx_line <= tx_parity_bit;
                        tx_state <= TX_STOP;
                    end
                    TX_STOP: begin
                        tx_line <= 1; // Stop bit
                        tx_state <= TX_IDLE;
                    end
                endcase
            end
        end
    end

    // Receiver
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP
    } rx_state_t;

    rx_state_t rx_state;
    logic [3:0] rx_bit_cnt;
    logic [7:0] rx_shift_reg;
    logic       rx_parity_bit;
    logic       rx_sample_tick;
    logic [7:0] rx_data_out;
    logic       rx_error;
    logic       rx_busy;
    logic [$clog2(BAUD_DIV)-1:0] rx_baud_cnt;
    logic [1:0] rx_sync;
    logic       rx_sampled;

    assign data_out = rx_data_out;
    assign UART_Error = rx_error;

    // Double-sampling RX for metastability
    always_ff @(posedge clk) begin
        rx_sync <= {rx_sync[0], RX};
        rx_sampled <= rx_sync[1];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state      <= RX_IDLE;
            rx_bit_cnt    <= 0;
            rx_shift_reg  <= 0;
            rx_parity_bit <= 0;
            rx_baud_cnt   <= 0;
            rx_data_out   <= 0;
            rx_error      <= 0;
            rx_busy       <= 0;
        end else begin
            rx_error <= 0;
            case (rx_state)
                RX_IDLE: begin
                    rx_busy <= 0;
                    if (~rx_sampled) begin // Start bit detected (falling edge)
                        rx_state <= RX_START;
                        rx_baud_cnt <= BAUD_DIV/2; // Sample in the middle of start bit
                    end
                end
                RX_START: begin
                    if (rx_baud_cnt == 0) begin
                        if (~rx_sampled) begin // Confirm still low
                            rx_state <= RX_DATA;
                            rx_bit_cnt <= 0;
                            rx_baud_cnt <= BAUD_DIV-1;
                        end else begin
                            rx_state <= RX_IDLE; // False start
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1;
                    end
                end
                RX_DATA: begin
                    if (rx_baud_cnt == 0) begin
                        rx_shift_reg <= {rx_sampled, rx_shift_reg[7:1]};
                        rx_bit_cnt <= rx_bit_cnt + 1;
                        rx_baud_cnt <= BAUD_DIV-1;
                        if (rx_bit_cnt == 7) begin
                            if (PARITY_EN != 0)
                                rx_state <= RX_PARITY;
                            else
                                rx_state <= RX_STOP;
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1;
                    end
                end
                RX_PARITY: begin
                    if (rx_baud_cnt == 0) begin
                        rx_parity_bit <= rx_sampled;
                        rx_state <= RX_STOP;
                        rx_baud_cnt <= BAUD_DIV-1;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1;
                    end
                end
                RX_STOP: begin
                    if (rx_baud_cnt == 0) begin
                        if (rx_sampled) begin // Stop bit should be high
                            // Parity check
                            if (PARITY_EN != 0) begin
                                logic parity_calc;
                                parity_calc = ^rx_shift_reg;
                                if (PARITY_TYPE == 1)
                                    parity_calc = ~parity_calc;
                                if (rx_parity_bit != parity_calc)
                                    rx_error <= 1;
                            end
                            rx_data_out <= rx_shift_reg;
                        end else begin
                            rx_error <= 1; // Framing error
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1;
                    end
                end
            endcase
        end
    end

endmodule