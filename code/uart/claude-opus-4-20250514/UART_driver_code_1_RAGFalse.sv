module UART_driver(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [8:0] data_in,    // Data to be transmitted (bit 8 is parity enable)
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [8:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Parameters for baud rate configuration
    parameter CLK_FREQ = 50_000_000;  // 50 MHz system clock
    parameter BAUD_RATE = 115200;     // Desired baud rate
    parameter BAUD_DIV = CLK_FREQ / BAUD_RATE;
    parameter BAUD_DIV_HALF = BAUD_DIV / 2;

    // State definitions for TX FSM
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_PARITY,
        TX_STOP1,
        TX_STOP2
    } tx_state_t;

    // State definitions for RX FSM
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_PARITY,
        RX_STOP1,
        RX_STOP2
    } rx_state_t;

    // Internal signals
    tx_state_t tx_state, tx_next_state;
    rx_state_t rx_state, rx_next_state;
    
    // TX signals
    logic [15:0] tx_baud_cnt;
    logic tx_baud_tick;
    logic [3:0] tx_bit_cnt;
    logic [7:0] tx_shift_reg;
    logic tx_parity_bit;
    logic tx_parity_enable;
    
    // RX signals
    logic [15:0] rx_baud_cnt;
    logic rx_baud_tick;
    logic [3:0] rx_bit_cnt;
    logic [7:0] rx_shift_reg;
    logic rx_parity_bit;
    logic rx_parity_enable;
    logic rx_parity_error;
    logic rx_frame_error;
    logic RX_sync, RX_sync_d;
    
    // Synchronize RX input to avoid metastability
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            RX_sync <= 1'b1;
            RX_sync_d <= 1'b1;
        end else begin
            RX_sync <= RX;
            RX_sync_d <= RX_sync;
        end
    end
    
    // TX Baud rate generator
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_baud_cnt <= 16'd0;
            tx_baud_tick <= 1'b0;
        end else begin
            if (tx_state == TX_IDLE) begin
                tx_baud_cnt <= 16'd0;
                tx_baud_tick <= 1'b0;
            end else if (tx_baud_cnt == BAUD_DIV - 1) begin
                tx_baud_cnt <= 16'd0;
                tx_baud_tick <= 1'b1;
            end else begin
                tx_baud_cnt <= tx_baud_cnt + 1'b1;
                tx_baud_tick <= 1'b0;
            end
        end
    end
    
    // RX Baud rate generator with mid-bit sampling
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_baud_cnt <= 16'd0;
            rx_baud_tick <= 1'b0;
        end else begin
            if (rx_state == RX_IDLE) begin
                rx_baud_cnt <= 16'd0;
                rx_baud_tick <= 1'b0;
            end else if (rx_state == RX_START && rx_baud_cnt == BAUD_DIV_HALF - 1) begin
                // Sample at mid-bit for start bit
                rx_baud_cnt <= 16'd0;
                rx_baud_tick <= 1'b1;
            end else if (rx_baud_cnt == BAUD_DIV - 1) begin
                rx_baud_cnt <= 16'd0;
                rx_baud_tick <= 1'b1;
            end else begin
                rx_baud_cnt <= rx_baud_cnt + 1'b1;
                rx_baud_tick <= 1'b0;
            end
        end
    end
    
    // TX FSM - State register
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            tx_state <= TX_IDLE;
        else
            tx_state <= tx_next_state;
    end
    
    // TX FSM - Next state logic
    always_comb begin
        tx_next_state = tx_state;
        
        case (tx_state)
            TX_IDLE: begin
                if (UART_Start)
                    tx_next_state = TX_START;
            end
            
            TX_START: begin
                if (tx_baud_tick)
                    tx_next_state = TX_DATA;
            end
            
            TX_DATA: begin
                if (tx_baud_tick && tx_bit_cnt == 4'd7) begin
                    if (tx_parity_enable)
                        tx_next_state = TX_PARITY;
                    else
                        tx_next_state = TX_STOP1;
                end
            end
            
            TX_PARITY: begin
                if (tx_baud_tick)
                    tx_next_state = TX_STOP1;
            end
            
            TX_STOP1: begin
                if (tx_baud_tick)
                    tx_next_state = TX_STOP2;
            end
            
            TX_STOP2: begin
                if (tx_baud_tick)
                    tx_next_state = TX_IDLE;
            end
            
            default: tx_next_state = TX_IDLE;
        endcase
    end
    
    // TX data path
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            TX <= 1'b1;
            tx_shift_reg <= 8'd0;
            tx_bit_cnt <= 4'd0;
            tx_parity_bit <= 1'b0;
            tx_parity_enable <= 1'b0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    TX <= 1'b1;
                    if (UART_Start) begin
                        tx_shift_reg <= data_in[7:0];
                        tx_parity_enable <= data_in[8];
                        tx_parity_bit <= ^data_in[7:0]; // Even parity
                        tx_bit_cnt <= 4'd0;
                    end
                end
                
                TX_START: begin
                    TX <= 1'b0; // Start bit
                end
                
                TX_DATA: begin
                    TX <= tx_shift_reg[0];
                    if (tx_baud_tick) begin
                        tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                        tx_bit_cnt <= tx_bit_cnt + 1'b1;
                    end
                end
                
                TX_PARITY: begin
                    TX <= tx_parity_bit;
                end
                
                TX_STOP1, TX_STOP2: begin
                    TX <= 1'b1; // Stop bits
                end
            endcase
        end
    end
    
    // RX FSM - State register
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            rx_state <= RX_IDLE;
        else
            rx_state <= rx_next_state;
    end
    
    // RX FSM - Next state logic
    always_comb begin
        rx_next_state = rx_state;
        
        case (rx_state)
            RX_IDLE: begin
                if (!RX_sync_d) // Start bit detected
                    rx_next_state = RX_START;
            end
            
            RX_START: begin
                if (rx_baud_tick) begin
                    if (!RX_sync_d) // Verify start bit
                        rx_next_state = RX_DATA;
                    else
                        rx_next_state = RX_IDLE; // False start
                end
            end
            
            RX_DATA: begin
                if (rx_baud_tick && rx_bit_cnt == 4'd7) begin
                    if (rx_parity_enable)
                        rx_next_state = RX_PARITY;
                    else
                        rx_next_state = RX_STOP1;
                end
            end
            
            RX_PARITY: begin
                if (rx_baud_tick)
                    rx_next_state = RX_STOP1;
            end
            
            RX_STOP1: begin
                if (rx_baud_tick)
                    rx_next_state = RX_STOP2;
            end
            
            RX_STOP2: begin
                if (rx_baud_tick)
                    rx_next_state = RX_IDLE;
            end
            
            default: rx_next_state = RX_IDLE;
        endcase
    end
    
    // RX data path
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_shift_reg <= 8'd0;
            rx_bit_cnt <= 4'd0;
            rx_parity_bit <= 1'b0;
            rx_parity_enable <= 1'b0;
            rx_parity_error <= 1'b0;
            rx_frame_error <= 1'b0;
            data_out <= 9'd0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    rx_bit_cnt <= 4'd0;
                    rx_parity_error <= 1'b0;
                    rx_frame_error <= 1'b0;
                    rx_parity_enable <= 1'b0; // Can be configured
                end
                
                RX_DATA: begin
                    if (rx_baud_tick) begin
                        rx_shift_reg <= {RX_sync_d, rx_shift_reg[7:1]};
                        rx_bit_cnt <= rx_bit_cnt + 1'b1;
                    end
                end
                
                RX_PARITY: begin
                    if (rx_baud_tick) begin
                        rx_parity_bit <= RX_sync_d;
                        // Check parity
                        if ((^rx_shift_reg) != RX_sync_d)
                            rx_parity_error <= 1'b1;
                    end
                end
                
                RX_STOP1: begin
                    if (rx_baud_tick && !RX_sync_d)
                        rx_frame_error <= 1'b1;
                end
                
                RX_STOP2: begin
                    if (rx_baud_tick) begin
                        if (!RX_sync_d)
                            rx_frame_error <= 1'b1;
                        else if (!rx_frame_error) begin
                            data_out <= {rx_parity_enable, rx_shift_reg};
                        end
                    end
                end
            endcase
        end
    end
    
    // Output assignments
    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy = (tx_state != TX_IDLE);
    assign UART_Error = rx_parity_error | rx_frame_error;

endmodule