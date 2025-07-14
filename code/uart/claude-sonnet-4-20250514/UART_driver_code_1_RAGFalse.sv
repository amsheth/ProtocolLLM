module UART_driver(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [8:0] data_in,    // Data to be transmitted (bit 8 = parity enable)
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [8:0] data_out,   // Received data (bit 8 = parity bit)
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Parameters for baud rate configuration
    parameter int CLOCK_FREQ = 100_000_000; // 100 MHz system clock
    parameter int BAUD_RATE = 115200;       // Default baud rate
    parameter int BAUD_DIVISOR = CLOCK_FREQ / (BAUD_RATE * 16); // Oversampling by 16
    
    // Internal signals for baud rate generation
    logic [15:0] baud_counter;
    logic        baud_tick;
    logic [3:0]  oversample_counter;
    logic        bit_tick;
    
    // Transmitter state machine
    typedef enum logic [3:0] {
        TX_IDLE,
        TX_START,
        TX_DATA_0, TX_DATA_1, TX_DATA_2, TX_DATA_3,
        TX_DATA_4, TX_DATA_5, TX_DATA_6, TX_DATA_7,
        TX_PARITY,
        TX_STOP_1,
        TX_STOP_2
    } tx_state_t;
    
    tx_state_t tx_state, tx_next_state;
    
    // Receiver state machine
    typedef enum logic [3:0] {
        RX_IDLE,
        RX_START,
        RX_DATA_0, RX_DATA_1, RX_DATA_2, RX_DATA_3,
        RX_DATA_4, RX_DATA_5, RX_DATA_6, RX_DATA_7,
        RX_PARITY,
        RX_STOP_1,
        RX_STOP_2
    } rx_state_t;
    
    rx_state_t rx_state, rx_next_state;
    
    // Internal registers
    logic [7:0] tx_data_reg;
    logic       tx_parity_enable;
    logic       tx_parity_bit;
    logic       tx_start_reg;
    
    logic [7:0] rx_data_reg;
    logic       rx_parity_bit;
    logic       rx_parity_enable;
    logic [2:0] rx_sample_counter;
    logic [2:0] rx_sample_buffer;
    logic       rx_bit_sample;
    logic       rx_error_reg;
    
    // Baud rate generator
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_counter <= 0;
            oversample_counter <= 0;
        end else begin
            if (baud_counter >= (BAUD_DIVISOR - 1)) begin
                baud_counter <= 0;
                oversample_counter <= oversample_counter + 1;
            end else begin
                baud_counter <= baud_counter + 1;
            end
        end
    end
    
    assign baud_tick = (baud_counter == 0);
    assign bit_tick = baud_tick && (oversample_counter == 0);
    
    // Input synchronization for RX
    logic [2:0] rx_sync;
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            rx_sync <= 3'b111;
        else
            rx_sync <= {rx_sync[1:0], RX};
    end
    
    // Majority voting for RX sampling
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sample_counter <= 0;
            rx_sample_buffer <= 0;
        end else if (baud_tick) begin
            case (oversample_counter)
                4'd6, 4'd7, 4'd8: begin
                    rx_sample_buffer <= rx_sample_buffer + rx_sync[2];
                    rx_sample_counter <= rx_sample_counter + 1;
                end
                4'd9: begin
                    rx_bit_sample <= (rx_sample_buffer >= 2);
                    rx_sample_counter <= 0;
                    rx_sample_buffer <= 0;
                end
                default: begin
                    // Do nothing
                end
            endcase
        end
    end
    
    // Transmitter state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            tx_data_reg <= 8'h00;
            tx_parity_enable <= 1'b0;
            tx_start_reg <= 1'b0;
        end else begin
            tx_state <= tx_next_state;
            
            // Capture data when starting transmission
            if (tx_state == TX_IDLE && UART_Start) begin
                tx_data_reg <= data_in[7:0];
                tx_parity_enable <= data_in[8];
                tx_start_reg <= 1'b1;
            end else if (tx_state != TX_IDLE) begin
                tx_start_reg <= 1'b0;
            end
        end
    end
    
    // Transmitter next state logic
    always_comb begin
        tx_next_state = tx_state;
        
        case (tx_state)
            TX_IDLE: begin
                if (UART_Start)
                    tx_next_state = TX_START;
            end
            
            TX_START: begin
                if (bit_tick)
                    tx_next_state = TX_DATA_0;
            end
            
            TX_DATA_0: if (bit_tick) tx_next_state = TX_DATA_1;
            TX_DATA_1: if (bit_tick) tx_next_state = TX_DATA_2;
            TX_DATA_2: if (bit_tick) tx_next_state = TX_DATA_3;
            TX_DATA_3: if (bit_tick) tx_next_state = TX_DATA_4;
            TX_DATA_4: if (bit_tick) tx_next_state = TX_DATA_5;
            TX_DATA_5: if (bit_tick) tx_next_state = TX_DATA_6;
            TX_DATA_6: if (bit_tick) tx_next_state = TX_DATA_7;
            TX_DATA_7: begin
                if (bit_tick) begin
                    if (tx_parity_enable)
                        tx_next_state = TX_PARITY;
                    else
                        tx_next_state = TX_STOP_1;
                end
            end
            
            TX_PARITY: begin
                if (bit_tick)
                    tx_next_state = TX_STOP_1;
            end
            
            TX_STOP_1: begin
                if (bit_tick)
                    tx_next_state = TX_STOP_2;
            end
            
            TX_STOP_2: begin
                if (bit_tick)
                    tx_next_state = TX_IDLE;
            end
            
            default: tx_next_state = TX_IDLE;
        endcase
    end
    
    // Calculate parity bit (even parity)
    always_comb begin
        tx_parity_bit = ^tx_data_reg;
    end
    
    // Transmitter output
    always_comb begin
        case (tx_state)
            TX_IDLE:    TX = 1'b1;
            TX_START:   TX = 1'b0;
            TX_DATA_0:  TX = tx_data_reg[0];
            TX_DATA_1:  TX = tx_data_reg[1];
            TX_DATA_2:  TX = tx_data_reg[2];
            TX_DATA_3:  TX = tx_data_reg[3];
            TX_DATA_4:  TX = tx_data_reg[4];
            TX_DATA_5:  TX = tx_data_reg[5];
            TX_DATA_6:  TX = tx_data_reg[6];
            TX_DATA_7:  TX = tx_data_reg[7];
            TX_PARITY:  TX = tx_parity_bit;
            TX_STOP_1:  TX = 1'b1;
            TX_STOP_2:  TX = 1'b1;
            default:    TX = 1'b1;
        endcase
    end
    
    // Receiver state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_data_reg <= 8'h00;
            rx_parity_bit <= 1'b0;
            rx_parity_enable <= 1'b0;
            rx_error_reg <= 1'b0;
        end else begin
            rx_state <= rx_next_state;
            
            // Capture data bits
            if (oversample_counter == 4'd9 && baud_tick) begin
                case (rx_state)
                    RX_DATA_0: rx_data_reg[0] <= rx_bit_sample;
                    RX_DATA_1: rx_data_reg[1] <= rx_bit_sample;
                    RX_DATA_2: rx_data_reg[2] <= rx_bit_sample;
                    RX_DATA_3: rx_data_reg[3] <= rx_bit_sample;
                    RX_DATA_4: rx_data_reg[4] <= rx_bit_sample;
                    RX_DATA_5: rx_data_reg[5] <= rx_bit_sample;
                    RX_DATA_6: rx_data_reg[6] <= rx_bit_sample;
                    RX_DATA_7: rx_data_reg[7] <= rx_bit_sample;
                    RX_PARITY: rx_parity_bit <= rx_bit_sample;
                    default: begin
                        // Do nothing
                    end
                endcase
            end
            
            // Error detection
            if (rx_state == RX_STOP_2 && oversample_counter == 4'd9 && baud_tick) begin
                // Check for framing error or parity error
                if (!rx_bit_sample) begin
                    rx_error_reg <= 1'b1; // Framing error
                end else if (rx_parity_enable && (rx_parity_bit != (^rx_data_reg))) begin
                    rx_error_reg <= 1'b1; // Parity error
                end else begin
                    rx_error_reg <= 1'b0;
                end
            end
        end
    end
    
    // Receiver next state logic
    always_comb begin
        rx_next_state = rx_state;
        
        case (rx_state)
            RX_IDLE: begin
                if (!rx_sync[2] && rx_sync[1]) // Start bit detected
                    rx_next_state = RX_START;
            end
            
            RX_START: begin
                if (oversample_counter == 4'd9 && baud_tick) begin
                    if (!rx_bit_sample) begin
                        rx_next_state = RX_DATA_0;
                        // Auto-detect parity based on transmission pattern
                        // This is a simplified approach - in practice, this would be configured
                        rx_parity_enable = 1'b1; // Assume parity is enabled
                    end else begin
                        rx_next_state = RX_IDLE; // False start
                    end
                end
            end
            
            RX_DATA_0: if (oversample_counter == 4'd9 && baud_tick) rx_next_state = RX_DATA_1;
            RX_DATA_1: if (oversample_counter == 4'd9 && baud_tick) rx_next_state = RX_DATA_2;
            RX_DATA_2: if (oversample_counter == 4'd9 && baud_tick) rx_next_state = RX_DATA_3;
            RX_DATA_3: if (oversample_counter == 4'd9 && baud_tick) rx_next_state = RX_DATA_4;
            RX_DATA_4: if (oversample_counter == 4'd9 && baud_tick) rx_next_state = RX_DATA_5;
            RX_DATA_5: if (oversample_counter == 4'd9 && baud_tick) rx_next_state = RX_DATA_6;
            RX_DATA_6: if (oversample_counter == 4'd9 && baud_tick) rx_next_state = RX_DATA_7;
            RX_DATA_7: begin
                if (oversample_counter == 4'd9 && baud_tick) begin
                    if (rx_parity_enable)
                        rx_next_state = RX_PARITY;
                    else
                        rx_next_state = RX_STOP_1;
                end
            end
            
            RX_PARITY: begin
                if (oversample_counter == 4'd9 && baud_tick)
                    rx_next_state = RX_STOP_1;
            end
            
            RX_STOP_1: begin
                if (oversample_counter == 4'd9 && baud_tick)
                    rx_next_state = RX_STOP_2;
            end
            
            RX_STOP_2: begin
                if (oversample_counter == 4'd9 && baud_tick)
                    rx_next_state = RX_IDLE;
            end
            
            default: rx_next_state = RX_IDLE;
        endcase
    end
    
    // Output assignments
    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy = (tx_state != TX_IDLE);
    assign UART_Error = rx_error_reg;
    assign data_out = {rx_parity_bit, rx_data_reg};

endmodule