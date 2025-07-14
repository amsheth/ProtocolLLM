module UART_driver (
    input  logic       clk,
    input  logic       rst,
    input  logic       UART_Start,
    input  logic [8:0] data_in,
    input  logic       RX,
    output logic       TX,
    output logic [8:0] data_out,
    output logic       UART_Ready,
    output logic       UART_Busy,
    output logic       UART_Error
);

// Configuration parameters
parameter BIT_RATE_DIVISOR = 16; // Baud rate divisor (adjust as needed)
parameter PARITY_TYPE = "NONE";   // Parity type: NONE, EVEN, ODD

// Internal states and counters
enum {
    IDLE,
    START_TRANSMIT,
    Transmitting,
    STOP_TRANSMIT,
    START_RECEIVE,
    Receiving
} State, Next_State;

reg [BIT_RATE_DIVISOR-1:0] brd_cnt;  // Baud rate counter
reg [3:0] tx_cnt;                    // Transmit bit counter
reg [3:0] rx_cnt;                    // Receive bit counter
reg parity_error;                     // Parity error flag
reg [8:0] rx_data;                   // Received data buffer
reg uart_busy;                       // UART busy flag
reg start_bit;                        // Start bit flag

// Baud rate generator
always @(posedge clk) begin
    if (rst) begin
        brd_cnt <= 0;
    end else begin
        if (brd_cnt == BIT_RATE_DIVISOR - 1) begin
            brd_cnt <= 0;
        end else begin
            brd_cnt <= brd_cnt + 1;
        end
    end
end

// Transmit logic
always @(posedge clk) begin
    if (rst) begin
        State <= IDLE;
        tx_cnt <= 0;
        uart_busy <= 0;
        TX <= 1;
    end else begin
        case (State)
            IDLE: begin
                if (!uart_busy && UART_Start) begin
                    State <= START_TRANSMIT;
                    start_bit <= 1; // Start bit is sent as 0, but here we set the state transition
                    uart_busy <= 1;
                end else begin
                    State <= IDLE;
                end
            end
            
            START_TRANSMIT: begin
                tx_cnt <= 0;
                TX <= 0; // Send start bit (0)
                State <= Transmitting;
            end
            
            Transmitting: begin
                if (brd_cnt == BIT_RATE_DIVISOR - 1) begin
                    case (tx_cnt)
                        0: begin // After start bit
                            tx_cnt <= 1;
                            TX <= data_in[0]; // Send first data bit
                        end
                        
                        1: begin
                            tx_cnt <= 2;
                            TX <= data_in[1];
                        end
                        
                        2: begin
                            tx_cnt <= 3;
                            TX <= data_in[2];
                        end
                        
                        3: begin
                            tx_cnt <= 4;
                            TX <= data_in[3];
                        end
                        
                        4: begin
                            tx_cnt <= 5;
                            TX <= data_in[4];
                        end
                        
                        5: begin
                            tx_cnt <= 6;
                            TX <= data_in[5];
                        end
                        
                        6: begin
                            tx_cnt <= 7;
                            TX <= data_in[6];
                        end
                        
                        7: begin
                            tx_cnt <= 8;
                            TX <= data_in[7];
                        end
                        
                        default: begin // Send parity bit if enabled and increment to stop bits
                            if (PARITY_TYPE != "NONE") begin
                                tx_cnt <= 9;
                                if (PARITY_TYPE == "EVEN") begin
                                    TX <= ($count_ones(data_in) % 2 == 0) ? 1 : 0;
                                end else begin // ODD parity
                                    TX <= (($count_ones(data_in) + 1) % 2 == 0) ? 1 : 0;
                                end
                            end else begin
                                tx_cnt <= 8; // Skip parity bit if not enabled
                            end
                        end
                    endcase
                    
                    if (tx_cnt >= 8) begin // If all data bits sent, proceed to stop bits
                        TX <= 1; // Send stop bit (1)
                        State <= STOP_TRANSMIT;
                        tx_cnt <= 0;
                    end
                end else begin
                    TX <= 1; // Hold TX high for the rest of the baud period if not sending data
                end
            end
            
            STOP_TRANSMIT: begin
                if (brd_cnt == BIT_RATE_DIVISOR - 1) begin
                    State <= IDLE;
                    uart_busy <= 0;
                    tx_cnt <= 0;
                end
            end
        endcase
    end
end

// Receive logic
always @(posedge clk) begin
    if (rst) begin
        rx_cnt <= 0;
        data_out <= 0;
        UART_Error <= 0;
        State <= IDLE;
    end else begin
        case (State)
            IDLE: begin
                if (!uart_busy && RX == 0) begin // Wait for start bit (RX is 0)
                    State <= START_RECEIVE;
                    rx_cnt <= 1; // First bit after start is first data bit
                end
            end
            
            START_RECEIVE: begin
                // Start bit received, now capture the next bits
                State <= Receiving;
                rx_cnt <= 0; // Reset counter for data bits
                data_out <= 0;
            end
            
            Receiving: begin
                if (brd_cnt == BIT_RATE_DIVISOR - 1) begin
                    case (rx_cnt)
                        0: begin // First bit after start is first data bit
                            rx_data[0] <= RX;
                            rx_cnt <= 1;
                        end
                        
                        1: begin
                            rx_data[1] <= RX;
                            rx_cnt <= 2;
                        end
                        
                        2: begin
                            rx_data[2] <= RX;
                            rx_cnt <= 3;
                        end
                        
                        3: begin
                            rx_data[3] <= RX;
                            rx_cnt <= 4;
                        end
                        
                        4: begin
                            rx_data[4] <= RX;
                            rx_cnt <= 5;
                        end
                        
                        5: begin
                            rx_data[5] <= RX;
                            rx_cnt <= 6;
                        end
                        
                        6: begin
                            rx_data[6] <= RX;
                            rx_cnt <= 7;
                        end
                        
                        7: begin // Last data bit
                            rx_data[7] <= RX;
                            if (PARITY_TYPE != "NONE") begin
                                // Calculate expected parity
                                if (PARITY_TYPE == "EVEN") begin
                                    expected_parity = ($count_ones(rx_data) % 2 == 0);
                                end else begin // ODD
                                    expected_parity = (($count_ones(rx_data) + 1) % 2 == 0);
                                end
                                if (RX != expected_parity) parity_error <= 1;
                            end
                            State <= IDLE;
                        end
                    endcase
                end
            end
        endcase
    end
end

// Output signals
assign UART_TX = TX;
assign UART_RX = rx_data; // You might need to adjust this based on your interface
assign UART_BUSY = uart_busy;
assign UART_ERROR = parity_error;

// Note: The above code assumes a certain pin structure. Adjust the assignments as per your hardware.

endmodule