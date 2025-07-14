module UART_driver(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [8:0] data_in,    // Data to be transmitted (bit 8 is parity enable)
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [8:0] data_out,   // Received data (bit 8 is parity bit)
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Parameters for baud rate configuration
    // For 9600 baud at 50MHz: BAUD_DIVISOR = 50000000 / (16 * 9600) = 325
    parameter BAUD_DIVISOR = 325;
    parameter BAUD_TICK = 16; // Oversampling factor
    
    // Internal signals
    logic [$clog2(BAUD_DIVISOR)-1:0] baud_counter;
    logic baud_tick;
    logic [$clog2(BAUD_TICK)-1:0] sample_counter;
    logic sample_tick;
    
    // Transmitter signals
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP1,
        TX_STOP2
    } tx_state_t;
    
    tx_state_t tx_state;
    logic [2:0] tx_bit_counter;
    logic [8:0] tx_shift_reg;
    logic tx_parity_bit;
    logic tx_parity_enable;
    
    // Receiver signals
    typedef enum logic [3:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP1,
        RX_STOP2,
        RX_DONE
    } rx_state_t;
    
    rx_state_t rx_state;
    logic [2:0] rx_bit_counter;
    logic [7:0] rx_shift_reg;
    logic rx_parity_bit;
    logic rx_parity_enable;
    logic rx_parity_calc;
    logic [2:0] rx_sample_counter;
    logic rx_data_valid;
    
    // Baud rate generator
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_counter <= 0;
            baud_tick <= 1'b0;
            sample_counter <= 0;
            sample_tick <= 1'b0;
        end else begin
            baud_tick <= 1'b0;
            sample_tick <= 1'b0;
            
            if (baud_counter == BAUD_DIVISOR - 1) begin
                baud_counter <= 0;
                baud_tick <= 1'b1;
                
                if (sample_counter == BAUD_TICK - 1) begin
                    sample_counter <= 0;
                    sample_tick <= 1'b1;
                end else begin
                    sample_counter <= sample_counter + 1;
                end
            end else begin
                baud_counter <= baud_counter + 1;
            end
        end
    end
    
    // Transmitter logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            TX <= 1'b1;
            tx_bit_counter <= 0;
            tx_shift_reg <= 0;
            tx_parity_bit <= 0;
            tx_parity_enable <= 0;
            UART_Busy <= 1'b0;
            UART_Ready <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    TX <= 1'b1;
                    UART_Busy <= 1'b0;
                    UART_Ready <= 1'b1;
                    
                    if (UART_Start) begin
                        tx_shift_reg <= data_in;
                        tx_parity_enable <= data_in[8];
                        tx_parity_bit <= ^data_in[7:0]; // Even parity
                        tx_state <= TX_START;
                        tx_bit_counter <= 0;
                        UART_Busy <= 1'b1;
                        UART_Ready <= 1'b0;
                    end
                end
                
                TX_START: begin
                    if (sample_tick) begin
                        TX <= 1'b0; // Start bit
                        tx_state <= TX_DATA;
                        tx_bit_counter <= 0;
                    end
                end
                
                TX_DATA: begin
                    if (sample_tick) begin
                        TX <= tx_shift_reg[tx_bit_counter];
                        tx_bit_counter <= tx_bit_counter + 1;
                        
                        if (tx_bit_counter == 7) begin
                            if (tx_parity_enable) begin
                                tx_state <= TX_PARITY;
                            end else begin
                                tx_state <= TX_STOP1;
                            end
                        end
                    end
                end
                
                TX_PARITY: begin
                    if (sample_tick) begin
                        TX <= tx_parity_bit;
                        tx_state <= TX_STOP1;
                    end
                end
                
                TX_STOP1: begin
                    if (sample_tick) begin
                        TX <= 1'b1; // First stop bit
                        tx_state <= TX_STOP2;
                    end
                end
                
                TX_STOP2: begin
                    if (sample_tick) begin
                        TX <= 1'b1; // Second stop bit
                        tx_state <= TX_IDLE;
                    end
                end
                
                default: tx_state <= TX_IDLE;
            endcase
        end
    end
    
    // Receiver logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_bit_counter <= 0;
            rx_shift_reg <= 0;
            rx_parity_bit <= 0;
            rx_parity_enable <= 0;
            rx_parity_calc <= 0;
            rx_sample_counter <= 0;
            rx_data_valid <= 1'b0;
            data_out <= 0;
            UART_Error <= 1'b0;
        end else begin
            rx_data_valid <= 1'b0;
            
            case (rx_state)
                RX_IDLE: begin
                    UART_Error <= 1'b0;
                    if (!RX) begin // Start bit detected
                        rx_state <= RX_START;
                        rx_sample_counter <= 0;
                        rx_bit_counter <= 0;
                    end
                end
                
                RX_START: begin
                    if (baud_tick) begin
                        rx_sample_counter <= rx_sample_counter + 1;
                        
                        if (rx_sample_counter == 7) begin // Sample at middle
                            if (RX == 1'b0) begin // Valid start bit
                                rx_state <= RX_DATA;
                                rx_sample_counter <= 0;
                                rx_bit_counter <= 0;
                                rx_parity_calc <= 1'b0;
                            end else begin
                                rx_state <= RX_IDLE; // False start
                            end
                        end
                    end
                end
                
                RX_DATA: begin
                    if (baud_tick) begin
                        rx_sample_counter <= rx_sample_counter + 1;
                        
                        if (rx_sample_counter == 7) begin // Sample at middle
                            rx_shift_reg[rx_bit_counter] <= RX;
                            rx_parity_calc <= rx_parity_calc ^ RX;
                            rx_bit_counter <= rx_bit_counter + 1;
                            rx_sample_counter <= 0;
                            
                            if (rx_bit_counter == 7) begin
                                // Check if next bit might be parity by looking ahead
                                rx_state <= RX_PARITY;
                            end
                        end
                    end
                end
                
                RX_PARITY: begin
                    if (baud_tick) begin
                        rx_sample_counter <= rx_sample_counter + 1;
                        
                        if (rx_sample_counter == 7) begin // Sample at middle
                            rx_parity_bit <= RX;
                            rx_sample_counter <= 0;
                            rx_state <= RX_STOP1;
                        end
                    end
                end
                
                RX_STOP1: begin
                    if (baud_tick) begin
                        rx_sample_counter <= rx_sample_counter + 1;
                        
                        if (rx_sample_counter == 7) begin // Sample at middle
                            if (RX == 1'b1) begin // Valid stop bit
                                rx_sample_counter <= 0;
                                rx_state <= RX_STOP2;
                            end else begin
                                UART_Error <= 1'b1; // Framing error
                                rx_state <= RX_IDLE;
                            end
                        end
                    end
                end
                
                RX_STOP2: begin
                    if (baud_tick) begin
                        rx_sample_counter <= rx_sample_counter + 1;
                        
                        if (rx_sample_counter == 7) begin // Sample at middle
                            if (RX == 1'b1) begin // Valid stop bit
                                rx_state <= RX_DONE;
                                
                                // Determine if parity was used based on received data pattern
                                // This is a simplified approach - in practice, parity usage
                                // should be configured externally
                                rx_parity_enable <= (rx_parity_bit != rx_parity_calc);
                                
                                if (rx_parity_enable && (rx_parity_bit != rx_parity_calc)) begin
                                    UART_Error <= 1'b1; // Parity error
                                end
                            end else begin
                                UART_Error <= 1'b1; // Framing error
                                rx_state <= RX_IDLE;
                            end
                        end
                    end
                end
                
                RX_DONE: begin
                    data_out <= {rx_parity_bit, rx_shift_reg};
                    rx_data_valid <= 1'b1;
                    rx_state <= RX_IDLE;
                end
                
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule