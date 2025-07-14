module UART_driver (
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

// Define parameters
parameter BIT_RATE         = 9600;  // Baud rate
parameter SYS_CLK_PERIOD   = 10;    // System clock period in ns
parameter BAUD_RATE_VALUE = 16;     // Baud rate multiplier

// Internal signals and states
enum logic [2:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state;
enum logic [2:0] {RX_IDLE, RX_START, RX_DATA, RX_PARITY, RX_STOP} rx_state;

// Clock enable for UART (to save power)
logic uart_clk, tx_baud, rx_baud;
logic [7:0] tx_data, rx_data;
logic [3:0] tx_counter, rx_counter;
logic tx_start, rx_start;
logic parity_error, framing_error;

// Generate UART clock (baud rate)
clk_wiz #(.CLK_IN_PERIOD(SYS_CLK_PERIOD), 
          .BAUD_RATE(BAUD_RATE_VALUE * BIT_RATE)) 
uart_clk_gen(
    .clk     (clk),
    .clk_out (uart_clk),
    .clk_out_b(tx_baud)
);

// Transmit FIFO (simplified as a single byte)
reg tx_fifo [7:0] = 0;
reg tx_ready = 1;
reg tx_busy = 0;

// Receive FIFO (simplified as a single byte)
reg rx_fifo [7:0] = 0;
reg rx_ready = 0;
reg rx_busy = 0;

// Parity calculation
function logic calculate_parity(logic [7:0] data, logic parity_bit);
    logic parity;
    parity = (data ^ parity_bit) ? 1'b0 : 1'b1;
    return parity;
endfunction

// Transmit state machine
always @(posedge uart_clk) begin
    if (rst) begin
        tx_state <= TX_IDLE;
        tx_data <= 0;
        tx_fifo <= data_in;
        tx_ready <= 1;
        tx_busy <= 0;
    end else begin
        case (tx_state)
            TX_IDLE:
                if (~tx_busy & ~UART_Busy & UART_Start) begin
                    tx_state <= TX_START;
                    tx_busy <= 1;
                    UART_Ready <= 0;
                    data_out <= 0;
                end
            TX_START:
                if (!tx_baud) begin
                    TX <= 1;  // Start bit (0)
                    tx_state <= TX_DATA;
                    tx_counter <= 0;
                end
            TX_DATA:
                if (!tx_baud) begin
                    tx_counter++;
                    if (!tx_counter[3]) begin
                        TX <= tx_fifo[7 - tx_counter];  // Shift out MSB first
                    end
                    if (tx_counter == 8) begin
                        tx_state <= TX_STOP;
                    end
                end
            TX_STOP:
                if (!tx_baud) begin
                    TX <= 0;  // Stop bit (1)
                    tx_state <= TX_IDLE;
                    tx_busy <= 0;
                    UART_Ready <= 1;
                end
        endcase
    end
end

// Receive state machine
always @(posedge uart_clk) begin
    if (rst) begin
        rx_state <= RX_IDLE;
        rx_data <= 0;
        rx_counter <= 0;
        rx_fifo <= 0;
        rx_busy <= 0;
        UART_Read <= 0;
        framing_error <= 0;
        parity_error <= 0;
    end else begin
        case (rx_state)
            RX_IDLE:
                if (~RX) begin  // Wait for start bit (0)
                    rx_state <= RX_START;
                    rx_counter <= 0;
                end
            RX_START:
                if (!rx_baud) begin
                    if (RX) begin  // Start bit is 0, if 1 then error
                        framing_error <= 1;
                    end
                    rx_state <= RX_DATA;
                    rx_counter <= 0;
                end
            RX_DATA:
                if (!rx_baud) begin
                    rx_counter++;
                    if (rx_counter <= 7) begin
                        rx_data[rx_counter-1] <= RX;
                    end else if (parameter PARITY) begin
                        rx_data[rx_counter-1] <= RX;  // Store parity bit
                        rx_state <= RX_PARITY;
                    end else begin
                        framing_error <= 1;  // Unexpected additional bits
                    end
                end
            RX_PARITY:
                if (!rx_baud) begin
                    // Check parity
                    if (parameter PARITY) begin
                        if (calculate_parity(rx_data[7:1], rx_data[0]) != (RX ? 1 : 0)) begin
                            parity_error <= 1;
                        end
                    end
                    rx_state <= RX_STOP;
                end
            RX_STOP:
                if (!rx_baud) begin
                    if (RX) begin  // Stop bit should be 1
                        framing_error <= 1;
                    end
                    rx_state <= RX_IDLE;
                    data_out <= rx_data;
                    rx_fifo <= data_out;
                    rx_ready <= 1;
                    rx_busy <= 0;
                end
        endcase
    end
end

// Error detection and reporting
always @(posedge clk) begin
    if (rst) begin
        UART_Error <= 0;
    end else begin
        if (framing_error | parity_error) begin
            UART_Error <= 1;
        end else begin
            UART_Error <= 0;
        end
    end
end

// Interface signals
assign RX = rx_state == RXIdle ? (RX ? 1 : 0) : 0;  // Receive line driver
assign TX = tx_state == TXIdle ? (TX ? 1 : 0) : 0;  // Transmit line driver

// Control signals
assign UART_Ready = tx_state == TX_IDLE & ~tx_busy;
assign UART_Busy = tx_state != TX_IDLE | rx_state != RX_IDLE;

// Output received data and control signals
assign data_out = rx_fifo;

endmodule