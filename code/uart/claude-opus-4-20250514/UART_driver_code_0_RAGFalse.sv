module UART_driver #(
    parameter CLK_FREQ = 50_000_000,  // System clock frequency in Hz
    parameter BAUD_RATE = 115200,     // Desired baud rate
    parameter DATA_BITS = 8,          // Number of data bits (7 or 8)
    parameter PARITY_EN = 0,          // Enable parity (0: disabled, 1: enabled)
    parameter PARITY_TYPE = 0,        // 0: even parity, 1: odd parity
    parameter STOP_BITS = 1           // Number of stop bits (1 or 2)
)(
    input  logic       clk,           // System clock
    input  logic       rst,           // Asynchronous reset
    input  logic       UART_Start,    // Signal to initiate transmission
    input  logic [7:0] data_in,       // Data to be transmitted
    input  logic       RX,            // UART receive line
    output logic       TX,            // UART transmit line
    output logic [7:0] data_out,      // Received data
    output logic       UART_Ready,    // Ready to transmit next byte
    output logic       UART_Busy,     // Indicates UART is currently transmitting
    output logic       UART_Error     // High if framing or parity error detected
);

    // Calculate clock divider for baud rate generation
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    // State definitions for TX and RX FSMs
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        PARITY_BIT,
        STOP_BIT,
        CLEANUP
    } uart_state_t;
    
    // Transmitter signals
    uart_state_t tx_state;
    logic [15:0] tx_clk_count;
    logic [2:0]  tx_bit_index;
    logic [7:0]  tx_data_reg;
    logic        tx_parity_bit;
    
    // Receiver signals
    uart_state_t rx_state;
    logic [15:0] rx_clk_count;
    logic [2:0]  rx_bit_index;
    logic [7:0]  rx_data_reg;
    logic        rx_parity_bit;
    logic        rx_parity_calc;
    logic        rx_frame_error;
    logic        rx_parity_error;
    logic        rx_data_ready;
    
    // RX synchronizer for metastability
    logic [2:0] rx_sync;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync <= 3'b111;
        end else begin
            rx_sync <= {rx_sync[1:0], RX};
        end
    end
    
    wire rx_in = rx_sync[2];
    
    // Parity calculation function
    function logic calc_parity(input logic [7:0] data, input logic parity_type);
        logic parity;
        parity = ^data;  // XOR all bits
        return parity_type ? ~parity : parity;  // odd or even parity
    endfunction
    
    // ==================== TRANSMITTER ====================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= IDLE;
            tx_clk_count <= 0;
            tx_bit_index <= 0;
            tx_data_reg <= 0;
            TX <= 1'b1;  // Idle state is high
            UART_Busy <= 1'b0;
            tx_parity_bit <= 1'b0;
        end else begin
            case (tx_state)
                IDLE: begin
                    TX <= 1'b1;
                    tx_clk_count <= 0;
                    tx_bit_index <= 0;
                    UART_Busy <= 1'b0;
                    
                    if (UART_Start) begin
                        tx_data_reg <= data_in;
                        UART_Busy <= 1'b1;
                        tx_state <= START_BIT;
                        if (PARITY_EN)
                            tx_parity_bit <= calc_parity(data_in, PARITY_TYPE);
                    end
                end
                
                START_BIT: begin
                    TX <= 1'b0;  // Start bit is low
                    
                    if (tx_clk_count < CLKS_PER_BIT - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        tx_state <= DATA_BITS;
                    end
                end
                
                DATA_BITS: begin
                    TX <= tx_data_reg[tx_bit_index];
                    
                    if (tx_clk_count < CLKS_PER_BIT - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        
                        if (tx_bit_index < DATA_BITS - 1) begin
                            tx_bit_index <= tx_bit_index + 1;
                        end else begin
                            tx_bit_index <= 0;
                            tx_state <= PARITY_EN ? PARITY_BIT : STOP_BIT;
                        end
                    end
                end
                
                PARITY_BIT: begin
                    TX <= tx_parity_bit;
                    
                    if (tx_clk_count < CLKS_PER_BIT - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        tx_state <= STOP_BIT;
                    end
                end
                
                STOP_BIT: begin
                    TX <= 1'b1;  // Stop bit is high
                    
                    if (tx_clk_count < CLKS_PER_BIT - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        
                        if (STOP_BITS == 2 && tx_bit_index == 0) begin
                            tx_bit_index <= 1;
                        end else begin
                            tx_state <= CLEANUP;
                            tx_bit_index <= 0;
                        end
                    end
                end
                
                CLEANUP: begin
                    UART_Busy <= 1'b0;
                    tx_state <= IDLE;
                end
                
                default: tx_state <= IDLE;
            endcase
        end
    end
    
    // ==================== RECEIVER ====================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= IDLE;
            rx_clk_count <= 0;
            rx_bit_index <= 0;
            rx_data_reg <= 0;
            rx_data_ready <= 1'b0;
            rx_frame_error <= 1'b0;
            rx_parity_error <= 1'b0;
            rx_parity_calc <= 1'b0;
        end else begin
            rx_data_ready <= 1'b0;  // Default
            
            case (rx_state)
                IDLE: begin
                    rx_clk_count <= 0;
                    rx_bit_index <= 0;
                    
                    if (rx_in == 1'b0) begin  // Start bit detected
                        rx_state <= START_BIT;
                        rx_frame_error <= 1'b0;
                        rx_parity_error <= 1'b0;
                    end
                end
                
                START_BIT: begin
                    if (rx_clk_count < (CLKS_PER_BIT - 1) / 2) begin
                        rx_clk_count <= rx_clk_count + 1;
                    end else begin
                        if (rx_in == 1'b0) begin  // Valid start bit
                            rx_clk_count <= 0;
                            rx_state <= DATA_BITS;
                            rx_parity_calc <= 1'b0;
                        end else begin  // False start bit
                            rx_state <= IDLE;
                        end
                    end
                end
                
                DATA_BITS: begin
                    if (rx_clk_count < CLKS_PER_BIT - 1) begin
                        rx_clk_count <= rx_clk_count + 1;
                    end else begin
                        rx_clk_count <= 0;
                        rx_data_reg[rx_bit_index] <= rx_in;
                        rx_parity_calc <= rx_parity_calc ^ rx_in;
                        
                        if (rx_bit_index < DATA_BITS - 1) begin
                            rx_bit_index <= rx_bit_index + 1;
                        end else begin
                            rx_bit_index <= 0;
                            rx_state <= PARITY_EN ? PARITY_BIT : STOP_BIT;
                        end
                    end
                end
                
                PARITY_BIT: begin
                    if (rx_clk_count < CLKS_PER_BIT - 1) begin
                        rx_clk_count <= rx_clk_count + 1;
                    end else begin
                        rx_clk_count <= 0;
                        rx_parity_bit <= rx_in;
                        
                        // Check parity
                        if (PARITY_TYPE == 0) begin  // Even parity
                            rx_parity_error <= (rx_parity_calc != rx_in);
                        end else begin  // Odd parity
                            rx_parity_error <= (rx_parity_calc == rx_in);
                        end
                        
                        rx_state <= STOP_BIT;
                    end
                end
                
                STOP_BIT: begin
                    if (rx_clk_count < CLKS_PER_BIT - 1) begin
                        rx_clk_count <= rx_clk_count + 1;
                    end else begin
                        rx_clk_count <= 0;
                        
                        if (rx_in == 1'b1) begin  // Valid stop bit
                            if (STOP_BITS == 2 && rx_bit_index == 0) begin
                                rx_bit_index <= 1;
                            end else begin
                                rx_state <= CLEANUP;
                                rx_data_ready <= 1'b1;
                                rx_bit_index <= 0;
                            end
                        end else begin  // Framing error
                            rx_frame_error <= 1'b1;
                            rx_state <= CLEANUP;
                        end
                    end
                end
                
                CLEANUP: begin
                    rx_state <= IDLE;
                end
                
                default: rx_state <= IDLE;
            endcase
        end
    end
    
    // Output assignments
    assign UART_Ready = ~UART_Busy;
    
    // Data output register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'b0;
        end else if (rx_data_ready && !rx_frame_error && (!PARITY_EN || !rx_parity_error)) begin
            data_out <= rx_data_reg;
        end
    end
    
    // Error flag
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            UART_Error <= 1'b0;
        end else begin
            if (rx_frame_error || (PARITY_EN && rx_parity_error)) begin
                UART_Error <= 1'b1;
            end else if (rx_state == IDLE) begin
                UART_Error <= 1'b0;
            end
        end
    end

endmodule