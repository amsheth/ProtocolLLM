module UART_driver (
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,   // Received data output
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

// Internal signals and constants
`define BAUD_RATE 16        // Baud rate divisor (adjust based on your system clock)

// Transmitter states
typedef enum {
    TX_IDLE,
    TX_START,
    TX_DATA,
    TX_PARITY,
    TX_STOP
} TxState;

// Receiver states
typedef enum {
    RX_IDLE,
    RX_START,
    RX_DATA,
    RX_PARITY,
    RX_STOP
} RxState;

// Internal signals
logic [7:0] rx_data;
RxState    rx_state;
TxState    tx_state;
logic      tx_busy, rx_ready, parity_error, framing_error;
logic      tx_start_edge, rx_start_edge;
logic      baud_tick;

// Baud rate generator
always @(posedge clk) begin
    static logic [`BAUD_RATE-1:0] baud_cnt = 0;
    if (rst) begin
        baud_cnt <= 0;
    end else begin
        if (baud_tick) begin
            if (baud_cnt == `BAUD_RATE - 1) begin
                baud_cnt <= 0;
            end else begin
                baud_cnt <= baud_cnt + 1;
            end
        end
    end
    baud_tick = (baud_cnt == `BAUD_RATE - 1);
end

// Transmitter logic
always @(posedge clk) begin
    if (rst) begin
        tx_state <= TX_IDLE;
        TX       <= 1;
        rx_data  <= 0;
        UART_Busy <= 0;
    end else begin
        case (tx_state)
            TX_IDLE:
                if (UART_Start && !tx_busy) begin
                    tx_state <= TX_START;
                    TX      <= 0; // Start bit (low)
                    UART_Ready <= 1;
                    UART_Busy <= 1;
                end
            TX_START:
                if (baud_tick) begin
                    tx_state <= TX_DATA;
                    TX      <= 1; // After start bit, send data
                end
            TX_DATA:
                if (baud_tick) begin
                    tx_data_bit <= data_in[tx_data_cnt];
                    TX          <= tx_data_bit;
                    if (tx_data_cnt < 7) begin
                        tx_data_cnt <= tx_data_cnt + 1;
                    end else begin
                        tx_state   <= TX_STOP;
                    end
                end
            TX_STOP:
                if (baud_tick) begin
                    TX      <= 1; // Stop bit (high)
                    tx_state <= TX_IDLE;
                    UART_Busy <= 0;
                end
        endcase
    end
end

// Receiver logic
always @(posedge clk) begin
    if (rst) begin
        rx_state <= RX_IDLE;
        data_out <= 0;
        UART_Error <= 0;
    end else begin
        case (rx_state)
            RX_IDLE:
                if (~RX && !rx_busy) begin // Wait for falling edge on RX (start bit)
                    rx_state <= RX_START;
                    rx_data_cnt <= 7;     // Start counting data bits
                    data_out <= 0;
                    rx_parity <= 1;       // Initialize parity check
                end
            RX_START:
                if (baud_tick) begin
                    rx_state <= RX_DATA;
                    rx_bit_count <= 0;    // Start counting received bits
                end
            RX_DATA:
                if (baud_tick) begin
                    data_out[rx_bit_count] <= RX;
                    rx_parity ^= RX;      // XOR to calculate parity
                    rx_bit_count <= rx_bit_count + 1;
                    if (rx_bit_count == 7) begin
                        rx_state <= RX_PARITY;
                    end
                end
            RX_PARITY:
                if (baud_tick) begin
                    if (parity_check && (rx_parity != parity)) begin
                        UART_Error <= 1; // Parity error detected
                    end
                    rx_state <= RX_STOP;
                end
            RX_STOP:
                if (baud_tick) begin
                    if (!RX) begin          // Check for framing error (no stop bit)
                        framing_error <= 1;
                        UART_Error <= 1;
                    end
                    rx_state <= RX_IDLE;
                    rx_ready <= 1;         // Signal that data is ready
                end
        endcase
    end
end

// Output assignments
assign UART_Ready = !tx_busy && !rx_busy;
assign tx_data_bit = (tx_data_cnt < 8) ? data_in[tx_data_cnt] : 1;

// Reset and control signals
always @(rst) begin
    if (rst) begin
        tx_state <= TX_IDLE;
        rx_state <= RX_IDLE;
        UART_Ready <= 1;
        UART_Busy <= 0;
        UART_Error <= 0;
        data_out <= 0;
    end
end

endmodule