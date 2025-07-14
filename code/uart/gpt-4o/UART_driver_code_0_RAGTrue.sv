module UART_driver(
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

    // Local parameters for baud rate configuration
    parameter BAUD_RATE_DIV = 104; // Example baud rate divisor value for 9600 bps
    parameter PARITY_ENABLE = 0;   // Set to 1 to enable parity checking and generation
    parameter PARITY_TYPE = 0;     // 0 for even parity, 1 for odd parity

    // Internal signals
    logic [7:0] tx_data_shift;
    logic [7:0] rx_data_shift;
    logic [3:0] tx_bit_cnt;
    logic [3:0] rx_bit_cnt;
    logic tx_start, rx_start;
    logic tx_done, rx_done;
    logic tx_parity, rx_parity, expected_parity;
    logic [15:0] baud_counter;

    // State machine for transmit and receive
    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        PARITY,
        STOP
    } uart_state_e;

    uart_state_e tx_state, rx_state;

    // Baud rate generator and state machines for transmit and receive
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all states and signals
            TX <= 1'b1;
            UART_Ready <= 1'b1;
            UART_Busy <= 1'b0;
            UART_Error <= 1'b0;
            data_out <= 8'b0;
            tx_state <= IDLE;
            rx_state <= IDLE;
            tx_bit_cnt <= 4'd0;
            rx_bit_cnt <= 4'd0;
            tx_data_shift <= 8'h00;
            rx_data_shift <= 8'h00;
            tx_parity <= 1'b0;
            rx_parity <= 1'b0;
            baud_counter <= 16'd0;
        end else begin
            // Baud rate counter
            baud_counter <= (baud_counter == BAUD_RATE_DIV - 1) ? 16'd0 : baud_counter + 1'b1;

            // UART Transmit State Machine
            case (tx_state)
                IDLE: begin
                    if (UART_Start & UART_Ready) begin
                        UART_Ready <= 1'b0;
                        UART_Busy <= 1'b1;
                        tx_data_shift <= data_in;
                        tx_parity <= ^data_in;
                        tx_bit_cnt <= 4'd0;
                        tx_state <= START;
                    end
                end
                
                START: begin
                    TX <= 1'b0; // Start bit
                    if (baud_counter == BAUD_RATE_DIV - 1)
                        tx_state <= DATA;
                end

                DATA: begin
                    TX <= tx_data_shift[0];
                    if (baud_counter == BAUD_RATE_DIV - 1) begin
                        tx_data_shift <= {1'b0, tx_data_shift[7:1]};
                        tx_bit_cnt <= tx_bit_cnt + 1'b1;
                        if (tx_bit_cnt == 4'd7)
                            tx_state <= (PARITY_ENABLE) ? PARITY : STOP;
                    end
                end

                PARITY: begin
                    TX <= (PARITY_TYPE) ? ~tx_parity : tx_parity;
                    if (baud_counter == BAUD_RATE_DIV - 1)
                        tx_state <= STOP;
                end

                STOP: begin
                    TX <= 1'b1; // Stop bit
                    if (baud_counter == BAUD_RATE_DIV - 1) begin
                        UART_Ready <= 1'b1;
                        UART_Busy <= 1'b0;
                        tx_state <= IDLE;
                    end
                end
            endcase

            // UART Receive State Machine
            case (rx_state)
                IDLE: begin
                    if (!RX) begin // Start bit detected
                        rx_start <= 1'b1;
                        rx_bit_cnt <= 4'd0;
                        rx_state <= START;
                    end
                end

                START: begin
                    if (baud_counter == BAUD_RATE_DIV/2) // Mid-point of START bit
                        rx_state <= DATA;
                end

                DATA: begin
                    if (baud_counter == BAUD_RATE_DIV - 1) begin
                        rx_data_shift <= {RX, rx_data_shift[7:1]};
                        rx_parity <= rx_parity ^ RX;
                        rx_bit_cnt <= rx_bit_cnt + 1'b1;
                        if (rx_bit_cnt == 4'd7)
                            rx_state <= (PARITY_ENABLE) ? PARITY : STOP;
                    end
                end

                PARITY: begin
                    expected_parity <= (PARITY_TYPE) ? ~rx_parity : rx_parity;
                    if (baud_counter == BAUD_RATE_DIV - 1) begin
                        if (expected_parity != RX)
                            UART_Error <= 1'b1;
                        rx_state <= STOP;
                    end
                end

                STOP: begin
                    if (baud_counter == BAUD_RATE_DIV - 1) begin
                        if (!RX) // Stop bit should be high
                            UART_Error <= 1'b1;
                        else
                            data_out <= rx_data_shift;
                        rx_state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule