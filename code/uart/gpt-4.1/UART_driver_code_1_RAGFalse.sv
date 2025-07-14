module UART_driver(
    input  logic        clk,         // System clock
    input  logic        rst,         // Asynchronous reset
    input  logic        UART_Start,  // Signal to initiate transmission
    input  logic [8:0]  data_in,     // Data to be transmitted (8 bits + parity enable in [8])
    input  logic        RX,          // UART receive line
    output logic        TX,          // UART transmit line
    output logic [8:0]  data_out,    // Received data (8 bits + parity enable in [8])
    output logic        UART_Ready,  // Ready to transmit next byte
    output logic        UART_Busy,   // Indicates UART is currently transmitting
    output logic        UART_Error   // High if framing or parity error detected
);

    // === Configurable Parameters ===
    parameter integer CLK_FREQ_HZ = 50_000_000; // System clock frequency
    parameter integer BAUD_RATE   = 115200;     // Default baud rate

    // Derived constants
    localparam integer BAUD_DIV = CLK_FREQ_HZ / BAUD_RATE;

    // === Transmit State Machine ===
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP1,
        TX_STOP2
    } tx_state_t;

    tx_state_t tx_state;
    logic [3:0] tx_bit_cnt;
    logic [7:0] tx_shift_reg;
    logic       tx_parity_bit;
    logic       tx_parity_en;
    logic [15:0] tx_baud_cnt;

    // === Receive State Machine ===
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP1,
        RX_STOP2
    } rx_state_t;

    rx_state_t rx_state;
    logic [3:0] rx_bit_cnt;
    logic [7:0] rx_shift_reg;
    logic       rx_parity_bit;
    logic       rx_parity_en;
    logic [15:0] rx_baud_cnt;
    logic [15:0] rx_baud_half;
    logic       rx_sampled;
    logic       rx_error;

    // === Output Registers ===
    logic [8:0] rx_data_out;
    logic       tx_busy, tx_ready;
    logic       rx_data_valid;

    // === Assign Outputs ===
    assign UART_Ready = tx_ready;
    assign UART_Busy  = tx_busy;
    assign UART_Error = rx_error;
    assign data_out   = rx_data_out;
    assign TX         = (tx_state == TX_IDLE) ? 1'b1 : // Idle line is high
                        (tx_state == TX_START) ? 1'b0 : // Start bit
                        (tx_state == TX_DATA)  ? tx_shift_reg[0] :
                        (tx_state == TX_PARITY)? tx_parity_bit :
                        1'b1; // Stop bits

    // === Transmit Logic ===
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state      <= TX_IDLE;
            tx_bit_cnt    <= 0;
            tx_shift_reg  <= 0;
            tx_parity_bit <= 0;
            tx_parity_en  <= 0;
            tx_baud_cnt   <= 0;
            tx_busy       <= 0;
            tx_ready      <= 1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_busy  <= 0;
                    tx_ready <= 1;
                    tx_baud_cnt <= 0;
                    if (UART_Start) begin
                        tx_shift_reg  <= data_in[7:0];
                        tx_parity_en  <= data_in[8];
                        tx_parity_bit <= ^data_in[7:0]; // Even parity
                        tx_bit_cnt    <= 0;
                        tx_state      <= TX_START;
                        tx_busy       <= 1;
                        tx_ready      <= 0;
                    end
                end
                TX_START: begin
                    if (tx_baud_cnt == BAUD_DIV-1) begin
                        tx_baud_cnt <= 0;
                        tx_state    <= TX_DATA;
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt + 1;
                    end
                end
                TX_DATA: begin
                    if (tx_baud_cnt == BAUD_DIV-1) begin
                        tx_baud_cnt <= 0;
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        tx_bit_cnt <= tx_bit_cnt + 1;
                        if (tx_bit_cnt == 7) begin
                            if (tx_parity_en)
                                tx_state <= TX_PARITY;
                            else
                                tx_state <= TX_STOP1;
                        end
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt + 1;
                    end
                end
                TX_PARITY: begin
                    if (tx_baud_cnt == BAUD_DIV-1) begin
                        tx_baud_cnt <= 0;
                        tx_state    <= TX_STOP1;
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt + 1;
                    end
                end
                TX_STOP1: begin
                    if (tx_baud_cnt == BAUD_DIV-1) begin
                        tx_baud_cnt <= 0;
                        tx_state    <= TX_STOP2;
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt + 1;
                    end
                end
                TX_STOP2: begin
                    if (tx_baud_cnt == BAUD_DIV-1) begin
                        tx_baud_cnt <= 0;
                        tx_state    <= TX_IDLE;
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt + 1;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // === Receive Logic ===
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state      <= RX_IDLE;
            rx_bit_cnt    <= 0;
            rx_shift_reg  <= 0;
            rx_parity_bit <= 0;
            rx_parity_en  <= 0;
            rx_baud_cnt   <= 0;
            rx_baud_half  <= 0;
            rx_data_out   <= 0;
            rx_data_valid <= 0;
            rx_error      <= 0;
        end else begin
            rx_data_valid <= 0;
            case (rx_state)
                RX_IDLE: begin
                    rx_error <= 0;
                    if (~RX) begin // Start bit detected (line goes low)
                        rx_baud_cnt  <= 0;
                        rx_baud_half <= BAUD_DIV/2;
                        rx_state     <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_baud_cnt == rx_baud_half) begin
                        if (~RX) begin // Confirm start bit still low
                            rx_baud_cnt <= 0;
                            rx_bit_cnt  <= 0;
                            rx_state    <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE; // False start bit
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt + 1;
                    end
                end
                RX_DATA: begin
                    if (rx_baud_cnt == BAUD_DIV-1) begin
                        rx_baud_cnt <= 0;
                        rx_shift_reg <= {RX, rx_shift_reg[7:1]};
                        rx_bit_cnt <= rx_bit_cnt + 1;
                        if (rx_bit_cnt == 7) begin
                            rx_parity_en <= 0; // Default: no parity
                            rx_state <= RX_STOP1;
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt + 1;
                    end
                end
                RX_PARITY: begin
                    if (rx_baud_cnt == BAUD_DIV-1) begin
                        rx_baud_cnt <= 0;
                        rx_parity_bit <= RX;
                        rx_state <= RX_STOP1;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt + 1;
                    end
                end
                RX_STOP1: begin
                    if (rx_baud_cnt == BAUD_DIV-1) begin
                        rx_baud_cnt <= 0;
                        if (RX) begin
                            rx_state <= RX_STOP2;
                        end else begin
                            rx_error <= 1; // Framing error
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt + 1;
                    end
                end
                RX_STOP2: begin
                    if (rx_baud_cnt == BAUD_DIV-1) begin
                        rx_baud_cnt <= 0;
                        if (RX) begin
                            // Parity check (if enabled)
                            if (rx_parity_en) begin
                                if (rx_parity_bit != ^rx_shift_reg) begin
                                    rx_error <= 1; // Parity error
                                end
                            end
                            rx_data_out   <= {rx_parity_en, rx_shift_reg};
                            rx_data_valid <= 1;
                        end else begin
                            rx_error <= 1; // Framing error
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt + 1;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule