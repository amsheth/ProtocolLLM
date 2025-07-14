module UART_driver(
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,   // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,  // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

// Configuration parameters (these can be parameterized for different baud rates and other settings)
localparam int CLK_FREQ_MHZ = 10;   // System clock frequency in MHz
localparam int BAUD_RATE = 9600;    // Desired baud rate
localparam int DATA_BITS = 8;       // Number of data bits (fixed to 8)
localparam int PARITY_ENABLE = 1;   // Enable parity bit: 1 - enabled, 0 - disabled
localparam logic PARITY_ODD_EVEN = 0;// Parity type: 0 - even, 1 - odd

// Calculate the number of system clock cycles per baud period
localparam int BAUD_PERIOD = CLK_FREQ_MHZ * 1_000_000 / BAUD_RATE;

// Internal signals and states
typedef enum logic [2:0] {IDLE, START, DATA, PARITY, STOP} state_t;
state_t tx_state, rx_state;
logic [3:0] bit_count_tx, bit_count_rx;
logic [7:0] rx_data_buffer;
logic tx_shift_reg [DATA_BITS + (PARITY_ENABLE ? 1 : 0) + 2]; // +2 for start and stop bits
logic parity_bit;

// TX state machine
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        tx_state <= IDLE;
        UART_Ready <= 1'b1;
        UART_Busy <= 1'b0;
        bit_count_tx <= '0;
        TX <= 1'b1; // Idle state for UART is high
        tx_shift_reg <= '1; // Start bit is low, all other bits are initialized to high
    end else begin
        case (tx_state)
            IDLE: begin
                if (UART_Start) begin
                    tx_state <= START;
                    UART_Ready <= 1'b0;
                    UART_Busy <= 1'b1;
                    bit_count_tx <= '0;
                    // Load data into shift register, calculate parity if needed
                    tx_shift_reg[DATA_BITS] = ^data_in; // Parity calculation (even)
                    if (PARITY_ODD_EVEN) begin
                        tx_shift_reg[DATA_BITS] = ~tx_shift_reg[DATA_BITS];
                    end
                    tx_shift_reg[DATA_BITS-1:0] <= data_in;
                end else begin
                    UART_Ready <= 1'b1;
                end
            end
            START: begin
                if (bit_count_tx == BAUD_PERIOD) begin
                    bit_count_tx <= '0;
                    tx_state <= DATA;
                end else begin
                    bit_count_tx <= bit_count_tx + 1;
                end
                TX <= 1'b0; // Start bit is low
            end
            DATA: begin
                if (bit_count_tx == BAUD_PERIOD) begin
                    bit_count_tx <= '0;
                    tx_shift_reg <= {tx_shift_reg[DATA_BITS+1:0], 1'b1}; // Shift out the data and load stop bits
                    if (bit_count_rx < DATA_BITS) begin
                        bit_count_rx <= bit_count_rx + 1;
                    end else begin
                        tx_state <= PARITY;
                        bit_count_rx <= '0; // Reset for parity state
                    end
                end else begin
                    bit_count_tx <= bit_count_tx + 1;
                end
                TX <= tx_shift_reg[DATA_BITS+2];
            end
            PARITY: begin
                if (bit_count_tx == BAUD_PERIOD) begin
                    bit_count_tx <= '0;
                    tx_state <= STOP;
                end else begin
                    bit_count_tx <= bit_count_tx + 1;
                end
                TX <= tx_shift_reg[DATA_BITS+1];
            end
            STOP: begin
                if (bit_count_tx == BAUD_PERIOD) begin
                    UART_Ready <= 1'b1;
                    UART_Busy <= 1'b0;
                    tx_state <= IDLE;
                end else begin
                    bit_count_tx <= bit_count_tx + 1;
                end
                TX <= 1'b1; // Stop bit is high
            end
        endcase
    end
end

// RX state machine
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_state <= IDLE;
        UART_Error <= 1'b0;
        data_out <= '0;
        bit_count_rx <= '0;
        parity_bit <= '0;
        rx_data_buffer <= '0;
    end else begin
        case (rx_state)
            IDLE: begin
                if (!RX) begin // Start bit detection
                    bit_count_rx <= 1;
                    rx_state <= START;
                end
            end
            START: begin
                if (bit_count_rx == BAUD_PERIOD/2) begin // Sample in the middle of start bit
                    if (RX) begin
                        UART_Error <= 1'b1; // Start bit error
                        rx_state <= IDLE;
                    end else begin
                        rx_state <= DATA;
                    end
                end else begin
                    bit_count_rx <= bit_count_rx + 1;
                end
            end
            DATA: begin
                if (bit_count_rx == BAUD_PERIOD) begin
                    rx_data_buffer <= {RX, rx_data_buffer[DATA_BITS-1:0]}; // Shift in the received data
                    if (bit_count_rx < DATA_BITS*BAUD_PERIOD) begin
                        bit_count_rx <= bit_count_rx + 1;
                    end else begin
                        rx_state <= PARITY;
                        parity_bit <= RX; // Capture parity bit
                    end
                end else begin
                    bit_count_rx <= bit_count_rx + 1;
                end
            end
            PARITY: begin
                if (bit_count_rx == BAUD_PERIOD) begin
                    if (PARITY_ENABLE) begin
                        // Parity check
                        logic expected_parity = ^rx_data_buffer; // Even parity calculation
                        if (PARITY_ODD_EVEN) begin
                            expected_parity = ~expected_parity;
                        end
                        if (parity_bit != expected_parity) begin
                            UART_Error <= 1'b1; // Parity error
                            rx_state <= IDLE;
                        end else begin
                            rx_state <= STOP;
                        end
                    end else begin
                        rx_state <= STOP;
                    end
                end else begin
                    bit_count_rx <= bit_count_rx + 1;
                end
            end
            STOP: begin
                if (bit_count_rx == BAUD_PERIOD) begin
                    // Sample in the middle of stop bit
                    if (!RX) begin
                        UART_Error <= 1'b1; // Stop bit error
                        rx_state <= IDLE;
                    end else begin
                        data_out <= rx_data_buffer; // Output received data
                        rx_state <= IDLE;
                    end
                end else begin
                    bit_count_rx <= bit_count_rx + 1;
                end
            end
        endcase
    end
end

endmodule