module UART_driver #(
    parameter CLK_FREQ = 50000000,  // System clock frequency in Hz
    parameter BAUD_RATE = 115200,   // Desired baud rate
    parameter PARITY_EN = 0,        // 0: No parity, 1: Even parity, 2: Odd parity
    parameter DATA_BITS = 8         // Number of data bits (typically 8)
)(
    input  logic       clk,         // System clock
    input  logic       rst,         // Asynchronous reset
    input  logic       UART_Start,  // Signal to initiate transmission
    input  logic [8:0] data_in,     // Data to be transmitted
    input  logic       RX,          // UART receive line
    output logic       TX,          // UART transmit line
    output logic [8:0] data_out,    // Received data
    output logic       UART_Ready,  // Ready to transmit next byte
    output logic       UART_Busy,   // Indicates UART is currently transmitting
    output logic       UART_Error   // High if framing or parity error detected
);

    // Calculate baud rate divider parameters (based on document formula)
    localparam integer BAUD_DIV = CLK_FREQ / (16 * BAUD_RATE);
    localparam integer SAMPLE_RATE = 16;
    
    // Internal signals
    logic [15:0] baud_counter;
    logic        baud_tick;
    logic        sample_tick;
    
    // Transmitter signals
    logic [3:0]  tx_state;
    logic [3:0]  tx_bit_count;
    logic [8:0]  tx_shift_reg;
    logic        tx_parity;
    
    // Receiver signals
    logic [3:0]  rx_state;
    logic [3:0]  rx_bit_count;
    logic [8:0]  rx_shift_reg;
    logic        rx_parity;
    logic [3:0]  sample_count;
    logic        rx_sync;
    logic        rx_d1, rx_d2;
    
    // State definitions
    typedef enum logic [3:0] {
        IDLE    = 4'b0000,
        START   = 4'b0001,
        DATA    = 4'b0010,
        PARITY  = 4'b0011,
        STOP1   = 4'b0100,
        STOP2   = 4'b0101,
        ERROR   = 4'b0110
    } uart_state_t;
    
    //=========================================================================
    // Baud Rate Generator
    //=========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_counter <= 16'd0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_counter == BAUD_DIV - 1) begin
                baud_counter <= 16'd0;
                baud_tick <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end
    
    // Generate sample tick (16x oversampling)
    logic [3:0] sample_counter;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sample_counter <= 4'd0;
            sample_tick <= 1'b0;
        end else if (baud_tick) begin
            sample_counter <= sample_counter + 1'b1;
            sample_tick <= (sample_counter == 4'd0);
        end else begin
            sample_tick <= 1'b0;
        end
    end
    
    //=========================================================================
    // Input Synchronization
    //=========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_d1 <= 1'b1;
            rx_d2 <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_d1 <= RX;
            rx_d2 <= rx_d1;
            rx_sync <= rx_d2;
        end
    end
    
    //=========================================================================
    // UART Transmitter
    //=========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            TX <= 1'b1;
            tx_state <= IDLE;
            tx_bit_count <= 4'd0;
            tx_shift_reg <= 9'd0;
            UART_Ready <= 1'b1;
            UART_Busy <= 1'b0;
            tx_parity <= 1'b0;
        end else begin
            case (tx_state)
                IDLE: begin
                    TX <= 1'b1;
                    UART_Ready <= 1'b1;
                    UART_Busy <= 1'b0;
                    if (UART_Start) begin
                        tx_shift_reg <= data_in;
                        tx_state <= START;
                        UART_Ready <= 1'b0;
                        UART_Busy <= 1'b1;
                        tx_bit_count <= 4'd0;
                        tx_parity <= (PARITY_EN == 2) ? 1'b1 : 1'b0; // Odd parity init
                    end
                end
                
                START: begin
                    if (sample_tick) begin
                        TX <= 1'b0; // Start bit
                        tx_state <= DATA;
                        tx_bit_count <= 4'd0;
                    end
                end
                
                DATA: begin
                    if (sample_tick) begin
                        TX <= tx_shift_reg[0];
                        tx_shift_reg <= {1'b0, tx_shift_reg[8:1]};
                        if (PARITY_EN != 0) begin
                            tx_parity <= tx_parity ^ tx_shift_reg[0];
                        end
                        tx_bit_count <= tx_bit_count + 1'b1;
                        if (tx_bit_count == DATA_BITS - 1) begin
                            tx_state <= (PARITY_EN != 0) ? PARITY : STOP1;
                        end
                    end
                end
                
                PARITY: begin
                    if (sample_tick) begin
                        TX <= tx_parity;
                        tx_state <= STOP1;
                    end
                end
                
                STOP1: begin
                    if (sample_tick) begin
                        TX <= 1'b1; // First stop bit
                        tx_state <= STOP2;
                    end
                end
                
                STOP2: begin
                    if (sample_tick) begin
                        TX <= 1'b1; // Second stop bit
                        tx_state <= IDLE;
                    end
                end
                
                default: tx_state <= IDLE;
            endcase
        end
    end
    
    //=========================================================================
    // UART Receiver
    //=========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= IDLE;
            rx_bit_count <= 4'd0;
            rx_shift_reg <= 9'd0;
            data_out <= 9'd0;
            UART_Error <= 1'b0;
            sample_count <= 4'd0;
            rx_parity <= 1'b0;
        end else begin
            case (rx_state)
                IDLE: begin
                    UART_Error <= 1'b0;
                    if (baud_tick && !rx_sync) begin // Start bit detected
                        rx_state <= START;
                        sample_count <= 4'd0;
                        rx_bit_count <= 4'd0;
                        rx_parity <= (PARITY_EN == 2) ? 1'b1 : 1'b0;
                    end
                end
                
                START: begin
                    if (baud_tick) begin
                        sample_count <= sample_count + 1'b1;
                        if (sample_count == 4'd7) begin // Middle of start bit
                            if (!rx_sync) begin // Valid start bit
                                rx_state <= DATA;
                                sample_count <= 4'd0;
                            end else begin // False start
                                rx_state <= IDLE;
                            end
                        end
                    end
                end
                
                DATA: begin
                    if (baud_tick) begin
                        sample_count <= sample_count + 1'b1;
                        if (sample_count == 4'd15) begin // Sample at bit center
                            rx_shift_reg <= {rx_sync, rx_shift_reg[8:1]};
                            if (PARITY_EN != 0) begin
                                rx_parity <= rx_parity ^ rx_sync;
                            end
                            rx_bit_count <= rx_bit_count + 1'b1;
                            sample_count <= 4'd0;
                            if (rx_bit_count == DATA_BITS - 1) begin
                                rx_state <= (PARITY_EN != 0) ? PARITY : STOP1;
                            end
                        end
                    end
                end
                
                PARITY: begin
                    if (baud_tick) begin
                        sample_count <= sample_count + 1'b1;
                        if (sample_count == 4'd15) begin
                            if (rx_sync != rx_parity) begin
                                UART_Error <= 1'b1; // Parity error
                            end
                            rx_state <= STOP1;
                            sample_count <= 4'd0;
                        end
                    end
                end
                
                STOP1: begin
                    if (baud_tick) begin
                        sample_count <= sample_count + 1'b1;
                        if (sample_count == 4'd15) begin
                            if (!rx_sync) begin
                                UART_Error <= 1'b1; // Framing error
                            end
                            rx_state <= STOP2;
                            sample_count <= 4'd0;
                        end
                    end
                end
                
                STOP2: begin
                    if (baud_tick) begin
                        sample_count <= sample_count + 1'b1;
                        if (sample_count == 4'd15) begin
                            if (!rx_sync) begin
                                UART_Error <= 1'b1; // Framing error
                            end else if (!UART_Error) begin
                                data_out <= rx_shift_reg; // Store received data
                            end
                            rx_state <= IDLE;
                        end
                    end
                end
                
                default: rx_state <= IDLE;
            endcase
        end
    end

endmodule