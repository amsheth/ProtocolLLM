module UART_driver #(
    parameter CLOCK_FREQ = 100_000_000,  // System clock frequency in Hz
    parameter BAUD_RATE = 115200,        // Baud rate
    parameter DATA_BITS = 8,             // Number of data bits (5-8)
    parameter PARITY_EN = 0,             // Parity enable (0=no parity, 1=enable)
    parameter PARITY_TYPE = 0,           // Parity type (0=even, 1=odd)
    parameter STOP_BITS = 1              // Number of stop bits (1 or 2)
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

    // Calculate baud rate divisor
    localparam BAUD_DIVISOR = CLOCK_FREQ / BAUD_RATE;
    localparam BAUD_COUNTER_WIDTH = $clog2(BAUD_DIVISOR);
    
    // Baud rate generator
    logic [BAUD_COUNTER_WIDTH-1:0] baud_counter;
    logic baud_tick;
    
    // Transmitter state machine
    typedef enum logic [3:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP
    } tx_state_t;
    
    tx_state_t tx_state, tx_next_state;
    
    // Receiver state machine
    typedef enum logic [3:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP
    } rx_state_t;
    
    rx_state_t rx_state, rx_next_state;
    
    // Transmitter registers
    logic [7:0] tx_data_reg;
    logic [2:0] tx_bit_count;
    logic tx_parity_bit;
    logic [1:0] tx_stop_count;
    
    // Receiver registers
    logic [7:0] rx_data_reg;
    logic [2:0] rx_bit_count;
    logic rx_parity_bit;
    logic rx_parity_calc;
    logic [1:0] rx_stop_count;
    logic [1:0] rx_sync;
    logic rx_start_detected;
    
    // Baud rate generator
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_counter <= 0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_counter == BAUD_DIVISOR - 1) begin
                baud_counter <= 0;
                baud_tick <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 1;
                baud_tick <= 1'b0;
            end
        end
    end
    
    // RX synchronizer for metastability prevention
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync <= 2'b11;
        end else begin
            rx_sync <= {rx_sync[0], RX};
        end
    end
    
    // Start bit detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_start_detected <= 1'b0;
        end else begin
            rx_start_detected <= (rx_sync == 2'b10); // Falling edge detection
        end
    end
    
    //===========================================
    // TRANSMITTER
    //===========================================
    
    // Transmitter state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= TX_IDLE;
        end else begin
            tx_state <= tx_next_state;
        end
    end
    
    // Transmitter next state logic
    always_comb begin
        tx_next_state = tx_state;
        
        case (tx_state)
            TX_IDLE: begin
                if (UART_Start && baud_tick) begin
                    tx_next_state = TX_START;
                end
            end
            
            TX_START: begin
                if (baud_tick) begin
                    tx_next_state = TX_DATA;
                end
            end
            
            TX_DATA: begin
                if (baud_tick && tx_bit_count == DATA_BITS - 1) begin
                    if (PARITY_EN) begin
                        tx_next_state = TX_PARITY;
                    end else begin
                        tx_next_state = TX_STOP;
                    end
                end
            end
            
            TX_PARITY: begin
                if (baud_tick) begin
                    tx_next_state = TX_STOP;
                end
            end
            
            TX_STOP: begin
                if (baud_tick && tx_stop_count == STOP_BITS - 1) begin
                    tx_next_state = TX_IDLE;
                end
            end
            
            default: tx_next_state = TX_IDLE;
        endcase
    end
    
    // Transmitter data path
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            TX <= 1'b1;
            tx_data_reg <= 8'h00;
            tx_bit_count <= 3'h0;
            tx_parity_bit <= 1'b0;
            tx_stop_count <= 2'h0;
            UART_Busy <= 1'b0;
            UART_Ready <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    TX <= 1'b1;
                    tx_bit_count <= 3'h0;
                    tx_stop_count <= 2'h0;
                    UART_Busy <= 1'b0;
                    UART_Ready <= 1'b1;
                    
                    if (UART_Start) begin
                        tx_data_reg <= data_in;
                        tx_parity_bit <= PARITY_TYPE ? ~(^data_in) : ^data_in;
                        UART_Busy <= 1'b1;
                        UART_Ready <= 1'b0;
                    end
                end
                
                TX_START: begin
                    TX <= 1'b0; // Start bit
                end
                
                TX_DATA: begin
                    TX <= tx_data_reg[tx_bit_count];
                    if (baud_tick) begin
                        tx_bit_count <= tx_bit_count + 1;
                    end
                end
                
                TX_PARITY: begin
                    TX <= tx_parity_bit;
                end
                
                TX_STOP: begin
                    TX <= 1'b1; // Stop bit
                    if (baud_tick) begin
                        tx_stop_count <= tx_stop_count + 1;
                    end
                end
                
                default: begin
                    TX <= 1'b1;
                end
            endcase
        end
    end
    
    //===========================================
    // RECEIVER
    //===========================================
    
    // Receiver state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= RX_IDLE;
        end else begin
            rx_state <= rx_next_state;
        end
    end
    
    // Receiver next state logic
    always_comb begin
        rx_next_state = rx_state;
        
        case (rx_state)
            RX_IDLE: begin
                if (rx_start_detected) begin
                    rx_next_state = RX_START;
                end
            end
            
            RX_START: begin
                if (baud_tick) begin
                    if (rx_sync[1] == 1'b0) begin // Valid start bit
                        rx_next_state = RX_DATA;
                    end else begin
                        rx_next_state = RX_IDLE; // False start
                    end
                end
            end
            
            RX_DATA: begin
                if (baud_tick && rx_bit_count == DATA_BITS - 1) begin
                    if (PARITY_EN) begin
                        rx_next_state = RX_PARITY;
                    end else begin
                        rx_next_state = RX_STOP;
                    end
                end
            end
            
            RX_PARITY: begin
                if (baud_tick) begin
                    rx_next_state = RX_STOP;
                end
            end
            
            RX_STOP: begin
                if (baud_tick && rx_stop_count == STOP_BITS - 1) begin
                    rx_next_state = RX_IDLE;
                end
            end
            
            default: rx_next_state = RX_IDLE;
        endcase
    end
    
    // Receiver data path
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'h00;
            rx_data_reg <= 8'h00;
            rx_bit_count <= 3'h0;
            rx_parity_bit <= 1'b0;
            rx_parity_calc <= 1'b0;
            rx_stop_count <= 2'h0;
            UART_Error <= 1'b0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    rx_bit_count <= 3'h0;
                    rx_stop_count <= 2'h0;
                    rx_parity_calc <= 1'b0;
                    UART_Error <= 1'b0;
                end
                
                RX_START: begin
                    // Wait for middle of start bit
                end
                
                RX_DATA: begin
                    if (baud_tick) begin
                        rx_data_reg[rx_bit_count] <= rx_sync[1];
                        rx_parity_calc <= rx_parity_calc ^ rx_sync[1];
                        rx_bit_count <= rx_bit_count + 1;
                    end
                end
                
                RX_PARITY: begin
                    if (baud_tick) begin
                        rx_parity_bit <= rx_sync[1];
                    end
                end
                
                RX_STOP: begin
                    if (baud_tick) begin
                        rx_stop_count <= rx_stop_count + 1;
                        
                        if (rx_stop_count == STOP_BITS - 1) begin
                            // Check for framing error
                            if (rx_sync[1] == 1'b1) begin
                                // Check for parity error
                                if (PARITY_EN) begin
                                    logic expected_parity = PARITY_TYPE ? ~rx_parity_calc : rx_parity_calc;
                                    if (rx_parity_bit == expected_parity) begin
                                        data_out <= rx_data_reg;
                                        UART_Error <= 1'b0;
                                    end else begin
                                        UART_Error <= 1'b1; // Parity error
                                    end
                                end else begin
                                    data_out <= rx_data_reg;
                                    UART_Error <= 1'b0;
                                end
                            end else begin
                                UART_Error <= 1'b1; // Framing error
                            end
                        end
                    end
                end
                
                default: begin
                    // Default case
                end
            endcase
        end
    end

endmodule