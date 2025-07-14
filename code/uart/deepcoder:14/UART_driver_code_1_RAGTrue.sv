module UART_driver (
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [8:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [8:0] data_out,   // Received data output
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

// Baud rate generator parameters
parameter BAUD_RATE = 9600;  // Configurable baud rate
parameter SYS_CLOCK = 100_000_000;  // System clock frequency in Hz

// Internal signals and variables
reg       tx_clk;         // Transmit clock
reg       rx_clk;         // Receive clock
reg       tx_state;       // Transmitter state machine
reg       rx_state;       // Receiver state machine
reg [8:0] tx_data;       // Transmitted data
reg [8:0] rx_data;       // Received data
reg       parity_enable;  // Enable parity checking
reg       parity;        // Calculated parity bit
reg       rx_start;       // Receive start flag
reg       tx_busy;        // Transmit busy flag
reg       rx_busy;        // Receive busy flag
reg       error;          // Error flag

// Internal counters
reg [3:0] tx_count;  // Transmit bit counter
reg [3:0] rx_count;  // Receive bit counter

// Baud rate generation
always @(posedge clk) begin
    if (rst) begin
        tx_clk <= 0;
        rx_clk <= 0;
    end else begin
        // Baud rate is SYS_CLOCK / (16 * BAUD_RATE)
        // Use a simple baud rate generator
        if (!tx_clk && !rx_clk) begin
            tx_clk <= (clk == 1'd1);  // Simple edge detection
            rx_clk <= (clk == 1'd1);
        end else begin
            tx_clk <= 0;
            rx_clk <= 0;
        end
    end
end

// Transmitter logic
always @(posedge clk) begin
    if (rst) begin
        tx_state <= 0;
        tx_data <= 0;
        tx_busy <= 0;
        tx_count <= 0;
        UART_Ready <= 1;
        UART_Busy <= 0;
    end else begin
        case (tx_state)
            0:  // Idle state
                if (UART_Start && !tx_busy && !UART_Busy) begin
                    tx_state <= 1;
                    tx_data <= data_in;
                    tx_count <= 0;
                    UART_Ready <= 0;
                    UART_Busy <= 1;
                end else begin
                    tx_state <= 0;
                end

            1:  // Start bit
                if (tx_clk) begin
                    TX <= 0;  // Start bit (0)
                    tx_state <= 2;
                    tx_count <= 1;
                end

            2:  // Data bits
                if (tx_clk) begin
                    if (tx_count < 8) begin
                        TX <= tx_data[7 - tx_count];
                        tx_count <= tx_count + 1;
                    end else begin
                        tx_state <= 3;
                        tx_count <= 0;
                    end
                end

            3:  // Parity bit (optional)
                if (tx_clk) begin
                    // Calculate parity
                    parity = 0;
                    for (int i = 0; i < 8; i++) begin
                        parity ^= tx_data[i];
                    end
                    // Drive parity bit (0 for even, 1 for odd)
                    if (parity_enable) begin
                        TX <= parity;
                    end else begin
                        TX <= 1;  // Default parity bit
                    end
                    tx_state <= 4;
                end

            4:  // Stop bit(s)
                if (tx_clk) begin
                    if (tx_count < 2) begin  // 2 stop bits
                        TX <= 1;  // Stop bit (1)
                        tx_count <= tx_count + 1;
                    end else begin
                        TX <= 1;  // Idle state after stop bits
                        tx_state <= 0;
                        tx_busy <= 0;
                        UART_Busy <= 0;
                        UART_Ready <= 1;
                    end
                end
            default:
                tx_state <= 0;
        endcase
    end
end

// Receiver logic
always @(posedge clk) begin
    if (rst) begin
        rx_state <= 0;
        rx_data <= 0;
        rx_busy <= 0;
        rx_count <= 0;
        data_out <= 0;
        UART_Error <= 0;
    end else begin
        if (!rx_busy && !tx_busy) begin
            case (rx_state)
                0:  // Idle state
                    if (!RX) begin  // Start bit (falling edge)
                        rx_state <= 1;
                        rx_busy <= 1;
                        rx_data <= 0;
                        rx_count <= 1;  // First bit is start bit
                        data_out <= 0;
                        UART_Error <= 0;
                    end

                1:  // Data bits
                    if (rx_clk) begin
                        if (rx_count < 9) begin  // 8 data bits + parity
                            data_out[rx_count - 1] <= RX;
                            rx_count <= rx_count + 1;
                        end else begin
                            rx_state <= 2;
                        end
                    end

                2:  // Stop bits
                    if (rx_clk) begin
                        if (rx_count < 11) begin  // 2 stop bits
                            rx_count <= rx_count + 1;
                        end else begin
                            rx_state <= 0;
                            rx_busy <= 0;
                            // Check parity (optional)
                            if (parity_enable) begin
                                parity = 0;
                                for (int i = 0; i < 8; i++) begin
                                    parity ^= data_out[i];
                                end
                                if (parity != data_out[8]) begin
                                    UART_Error <= 1;
                                end
                            end
                        end
                    end
                default:
                    rx_state <= 0;
            endcase
        end
    end
end

// Output assignments
assign TX = tx_state == 1 || tx_state == 2 || tx_state == 3 || tx_state == 4;

endmodule