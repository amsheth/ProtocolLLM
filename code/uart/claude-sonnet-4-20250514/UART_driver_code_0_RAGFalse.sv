module UART_driver #(
    parameter CLOCK_FREQ = 100_000_000,  // System clock frequency in Hz
    parameter BAUD_RATE = 9600,          // Baud rate
    parameter DATA_BITS = 8,             // Number of data bits (5-8)
    parameter PARITY_EN = 1,             // Enable parity (0=disabled, 1=enabled)
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

    // Calculate baud rate divider
    localparam BAUD_TICK = CLOCK_FREQ / BAUD_RATE;
    localparam BAUD_TICK_HALF = BAUD_TICK / 2;
    
    // State definitions for transmitter
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP
    } tx_state_t;
    
    // State definitions for receiver
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP
    } rx_state_t;
    
    // Transmitter signals
    tx_state_t tx_state, tx_next_state;
    logic [$clog2(BAUD_TICK)-1:0] tx_baud_counter;
    logic [3:0] tx_bit_counter;
    logic [7:0] tx_shift_reg;
    logic tx_parity_bit;
    logic tx_baud_tick;
    logic [1:0] tx_stop_counter;
    
    // Receiver signals
    rx_state_t rx_state, rx_next_state;
    logic [$clog2(BAUD_TICK)-1:0] rx_baud_counter;
    logic [3:0] rx_bit_counter;
    logic [7:0] rx_shift_reg;
    logic rx_parity_bit;
    logic rx_baud_tick;
    logic rx_start_tick;
    logic [1:0] rx_stop_counter;
    logic [2:0] rx_sync;
    logic rx_error_frame, rx_error_parity;
    logic data_ready;
    
    // Baud rate generation for transmitter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_baud_counter <= 0;
            tx_baud_tick <= 0;
        end else begin
            if (tx_state == TX_IDLE) begin
                tx_baud_counter <= 0;
                tx_baud_tick <= 0;
            end else if (tx_baud_counter == BAUD_TICK - 1) begin
                tx_baud_counter <= 0;
                tx_baud_tick <= 1;
            end else begin
                tx_baud_counter <= tx_baud_counter + 1;
                tx_baud_tick <= 0;
            end
        end
    end
    
    // Baud rate generation for receiver
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_baud_counter <= 0;
            rx_baud_tick <= 0;
            rx_start_tick <= 0;
        end else begin
            if (rx_state == RX_IDLE) begin
                rx_baud_counter <= 0;
                rx_baud_tick <= 0;
                rx_start_tick <= 0;
            end else if (rx_state == RX_START) begin
                if (rx_baud_counter == BAUD_TICK_HALF - 1) begin
                    rx_baud_counter <= 0;
                    rx_start_tick <= 1;
                end else begin
                    rx_baud_counter <= rx_baud_counter + 1;
                    rx_start_tick <= 0;
                end
            end else if (rx_baud_counter == BAUD_TICK - 1) begin
                rx_baud_counter <= 0;
                rx_baud_tick <= 1;
            end else begin
                rx_baud_counter <= rx_baud_counter + 1;
                rx_baud_tick <= 0;
            end
        end
    end
    
    // RX synchronizer
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync <= 3'b111;
        end else begin
            rx_sync <= {rx_sync[1:0], RX};
        end
    end
    
    // Transmitter state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= TX_IDLE;
        end else begin
            tx_state <= tx_next_state;
        end
    end
    
    always_comb begin
        tx_next_state = tx_state;
        
        case (tx_state)
            TX_IDLE: begin
                if (UART_Start) begin
                    tx_next_state = TX_START;
                end
            end
            
            TX_START: begin
                if (tx_baud_tick) begin
                    tx_next_state = TX_DATA;
                end
            end
            
            TX_DATA: begin
                if (tx_baud_tick && tx_bit_counter == DATA_BITS - 1) begin
                    if (PARITY_EN) begin
                        tx_next_state = TX_PARITY;
                    end else begin
                        tx_next_state = TX_STOP;
                    end
                end
            end
            
            TX_PARITY: begin
                if (tx_baud_tick) begin
                    tx_next_state = TX_STOP;
                end
            end
            
            TX_STOP: begin
                if (tx_baud_tick && tx_stop_counter == STOP_BITS - 1) begin
                    tx_next_state = TX_IDLE;
                end
            end
        endcase
    end
    
    // Transmitter data path
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg <= 8'h00;
            tx_bit_counter <= 0;
            tx_parity_bit <= 0;
            tx_stop_counter <= 0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    if (UART_Start) begin
                        tx_shift_reg <= data_in;
                        tx_bit_counter <= 0;
                        tx_stop_counter <= 0;
                        // Calculate parity
                        if (PARITY_EN) begin
                            tx_parity_bit <= PARITY_TYPE ? ~(^data_in) : ^data_in;
                        end
                    end
                end
                
                TX_DATA: begin
                    if (tx_baud_tick) begin
                        tx_shift_reg <= tx_shift_reg >> 1;
                        tx_bit_counter <= tx_bit_counter + 1;
                    end
                end
                
                TX_STOP: begin
                    if (tx_baud_tick) begin
                        tx_stop_counter <= tx_stop_counter + 1;
                    end
                end
            endcase
        end
    end
    
    // Receiver state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= RX_IDLE;
        end else begin
            rx_state <= rx_next_state;
        end
    end
    
    always_comb begin
        rx_next_state = rx_state;
        
        case (rx_state)
            RX_IDLE: begin
                if (rx_sync[2:1] == 2'b10) begin  // Detect start bit
                    rx_next_state = RX_START;
                end
            end
            
            RX_START: begin
                if (rx_start_tick) begin
                    if (rx_sync[2] == 0) begin  // Validate start bit
                        rx_next_state = RX_DATA;
                    end else begin
                        rx_next_state = RX_IDLE;  // False start
                    end
                end
            end
            
            RX_DATA: begin
                if (rx_baud_tick && rx_bit_counter == DATA_BITS - 1) begin
                    if (PARITY_EN) begin
                        rx_next_state = RX_PARITY;
                    end else begin
                        rx_next_state = RX_STOP;
                    end
                end
            end
            
            RX_PARITY: begin
                if (rx_baud_tick) begin
                    rx_next_state = RX_STOP;
                end
            end
            
            RX_STOP: begin
                if (rx_baud_tick && rx_stop_counter == STOP_BITS - 1) begin
                    rx_next_state = RX_IDLE;
                end
            end
        endcase
    end
    
    // Receiver data path
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_shift_reg <= 8'h00;
            rx_bit_counter <= 0;
            rx_parity_bit <= 0;
            rx_stop_counter <= 0;
            rx_error_frame <= 0;
            rx_error_parity <= 0;
            data_ready <= 0;
        end else begin
            data_ready <= 0;
            
            case (rx_state)
                RX_IDLE: begin
                    rx_bit_counter <= 0;
                    rx_stop_counter <= 0;
                    rx_error_frame <= 0;
                    rx_error_parity <= 0;
                end
                
                RX_DATA: begin
                    if (rx_baud_tick) begin
                        rx_shift_reg <= {rx_sync[2], rx_shift_reg[7:1]};
                        rx_bit_counter <= rx_bit_counter + 1;
                    end
                end
                
                RX_PARITY: begin
                    if (rx_baud_tick) begin
                        rx_parity_bit <= rx_sync[2];
                        // Check parity
                        if (PARITY_EN) begin
                            if (PARITY_TYPE) begin  // Odd parity
                                rx_error_parity <= (rx_sync[2] != ~(^rx_shift_reg));
                            end else begin  // Even parity
                                rx_error_parity <= (rx_sync[2] != (^rx_shift_reg));
                            end
                        end
                    end
                end
                
                RX_STOP: begin
                    if (rx_baud_tick) begin
                        if (rx_sync[2] == 0) begin  // Stop bit should be high
                            rx_error_frame <= 1;
                        end
                        rx_stop_counter <= rx_stop_counter + 1;
                        
                        if (rx_stop_counter == STOP_BITS - 1) begin
                            data_ready <= 1;
                        end
                    end
                end
            endcase
        end
    end
    
    // Output assignments
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            TX <= 1;
            data_out <= 8'h00;
            UART_Error <= 0;
        end else begin
            // TX output
            case (tx_state)
                TX_IDLE:   TX <= 1;
                TX_START:  TX <= 0;
                TX_DATA:   TX <= tx_shift_reg[0];
                TX_PARITY: TX <= tx_parity_bit;
                TX_STOP:   TX <= 1;
            endcase
            
            // Data output
            if (data_ready) begin
                data_out <= rx_shift_reg;
            end
            
            // Error output
            UART_Error <= rx_error_frame | rx_error_parity;
        end
    end
    
    // Status signals
    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy = (tx_state != TX_IDLE);

endmodule