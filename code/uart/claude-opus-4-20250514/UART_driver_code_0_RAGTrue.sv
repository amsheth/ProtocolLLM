module UART_driver #(
    parameter CLK_FREQ = 50_000_000,  // System clock frequency in Hz
    parameter BAUD_RATE = 115200,     // Desired baud rate
    parameter PARITY_EN = 0,          // 0: No parity, 1: Even parity, 2: Odd parity
    parameter STOP_BITS = 1           // Number of stop bits (1 or 2)
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

    // Calculate baud rate generator parameters (as per document specification)
    localparam integer BAUD_DIV = CLK_FREQ / (16 * BAUD_RATE);
    localparam integer BAUD_CNT_MAX = BAUD_DIV - 1;
    
    // Internal signals
    logic [$clog2(BAUD_CNT_MAX+1)-1:0] baud_counter;
    logic baud_tick;
    logic tx_start, rx_data_ready;
    logic rx_frame_error, rx_parity_error;
    
    // Baud rate generator (16x oversampling)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_counter <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_counter == BAUD_CNT_MAX) begin
                baud_counter <= '0;
                baud_tick <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end
    
    // Transmitter instance
    UART_transmitter #(
        .PARITY_EN(PARITY_EN),
        .STOP_BITS(STOP_BITS)
    ) tx_inst (
        .clk(clk),
        .rst(rst),
        .baud_tick(baud_tick),
        .tx_start(UART_Start),
        .data_in(data_in),
        .TX(TX),
        .tx_ready(UART_Ready),
        .tx_busy(UART_Busy)
    );
    
    // Receiver instance
    UART_receiver #(
        .PARITY_EN(PARITY_EN),
        .STOP_BITS(STOP_BITS)
    ) rx_inst (
        .clk(clk),
        .rst(rst),
        .baud_tick(baud_tick),
        .RX(RX),
        .data_out(data_out),
        .rx_ready(rx_data_ready),
        .frame_error(rx_frame_error),
        .parity_error(rx_parity_error)
    );
    
    // Error detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            UART_Error <= 1'b0;
        end else begin
            UART_Error <= rx_frame_error | rx_parity_error;
        end
    end

endmodule

// UART Transmitter Module
module UART_transmitter #(
    parameter PARITY_EN = 0,
    parameter STOP_BITS = 1
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       baud_tick,
    input  logic       tx_start,
    input  logic [7:0] data_in,
    output logic       TX,
    output logic       tx_ready,
    output logic       tx_busy
);

    // State machine states
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        PARITY_BIT,
        STOP_BIT
    } tx_state_t;
    
    tx_state_t state, next_state;
    logic [7:0] tx_data_reg;
    logic [3:0] bit_counter;
    logic [3:0] tick_counter;
    logic parity_bit;
    logic [1:0] stop_bit_counter;
    
    // Calculate parity
    always_comb begin
        if (PARITY_EN == 1) // Even parity
            parity_bit = ^tx_data_reg;
        else if (PARITY_EN == 2) // Odd parity
            parity_bit = ~^tx_data_reg;
        else
            parity_bit = 1'b0;
    end
    
    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx_data_reg <= 8'h00;
            bit_counter <= 4'd0;
            tick_counter <= 4'd0;
            stop_bit_counter <= 2'd0;
            TX <= 1'b1; // Idle high
        end else begin
            if (baud_tick) begin
                case (state)
                    IDLE: begin
                        TX <= 1'b1;
                        if (tx_start) begin
                            tx_data_reg <= data_in;
                            state <= START_BIT;
                            tick_counter <= 4'd0;
                        end
                    end
                    
                    START_BIT: begin
                        TX <= 1'b0; // Start bit
                        if (tick_counter == 4'd15) begin
                            state <= DATA_BITS;
                            tick_counter <= 4'd0;
                            bit_counter <= 4'd0;
                        end else begin
                            tick_counter <= tick_counter + 1'b1;
                        end
                    end
                    
                    DATA_BITS: begin
                        TX <= tx_data_reg[bit_counter];
                        if (tick_counter == 4'd15) begin
                            tick_counter <= 4'd0;
                            if (bit_counter == 4'd7) begin
                                if (PARITY_EN != 0)
                                    state <= PARITY_BIT;
                                else
                                    state <= STOP_BIT;
                                stop_bit_counter <= 2'd0;
                            end else begin
                                bit_counter <= bit_counter + 1'b1;
                            end
                        end else begin
                            tick_counter <= tick_counter + 1'b1;
                        end
                    end
                    
                    PARITY_BIT: begin
                        TX <= parity_bit;
                        if (tick_counter == 4'd15) begin
                            state <= STOP_BIT;
                            tick_counter <= 4'd0;
                            stop_bit_counter <= 2'd0;
                        end else begin
                            tick_counter <= tick_counter + 1'b1;
                        end
                    end
                    
                    STOP_BIT: begin
                        TX <= 1'b1; // Stop bit(s)
                        if (tick_counter == 4'd15) begin
                            tick_counter <= 4'd0;
                            if (stop_bit_counter == STOP_BITS - 1) begin
                                state <= IDLE;
                            end else begin
                                stop_bit_counter <= stop_bit_counter + 1'b1;
                            end
                        end else begin
                            tick_counter <= tick_counter + 1'b1;
                        end
                    end
                    
                    default: state <= IDLE;
                endcase
            end
        end
    end
    
    // Output assignments
    assign tx_ready = (state == IDLE);
    assign tx_busy = (state != IDLE);

endmodule

// UART Receiver Module
module UART_receiver #(
    parameter PARITY_EN = 0,
    parameter STOP_BITS = 1
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       baud_tick,
    input  logic       RX,
    output logic [7:0] data_out,
    output logic       rx_ready,
    output logic       frame_error,
    output logic       parity_error
);

    // State machine states
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        PARITY_BIT,
        STOP_BIT
    } rx_state_t;
    
    rx_state_t state;
    logic [7:0] rx_data_reg;
    logic [3:0] bit_counter;
    logic [3:0] tick_counter;
    logic rx_sync1, rx_sync2, rx_sync;
    logic parity_bit_received;
    logic parity_calculated;
    
    // Synchronize RX input (metastability protection)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_sync1 <= RX;
            rx_sync2 <= rx_sync1;
            rx_sync <= rx_sync2;
        end
    end
    
    // Calculate expected parity
    always_comb begin
        if (PARITY_EN == 1) // Even parity
            parity_calculated = ^rx_data_reg;
        else if (PARITY_EN == 2) // Odd parity
            parity_calculated = ~^rx_data_reg;
        else
            parity_calculated = 1'b0;
    end
    
    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            rx_data_reg <= 8'h00;
            bit_counter <= 4'd0;
            tick_counter <= 4'd0;
            rx_ready <= 1'b0;
            frame_error <= 1'b0;
            parity_error <= 1'b0;
            data_out <= 8'h00;
            parity_bit_received <= 1'b0;
        end else begin
            rx_ready <= 1'b0; // Default
            
            if (baud_tick) begin
                case (state)
                    IDLE: begin
                        frame_error <= 1'b0;
                        parity_error <= 1'b0;
                        if (~rx_sync) begin // Start bit detected
                            state <= START_BIT;
                            tick_counter <= 4'd0;
                        end
                    end
                    
                    START_BIT: begin
                        if (tick_counter == 4'd7) begin // Sample at middle
                            if (~rx_sync) begin // Valid start bit
                                tick_counter <= 4'd0;
                                state <= DATA_BITS;
                                bit_counter <= 4'd0;
                            end else begin // False start bit
                                state <= IDLE;
                            end
                        end else begin
                            tick_counter <= tick_counter + 1'b1;
                        end
                    end
                    
                    DATA_BITS: begin
                        if (tick_counter == 4'd15) begin // Sample at middle
                            rx_data_reg[bit_counter] <= rx_sync;
                            tick_counter <= 4'd0;
                            if (bit_counter == 4'd7) begin
                                if (PARITY_EN != 0)
                                    state <= PARITY_BIT;
                                else
                                    state <= STOP_BIT;
                            end else begin
                                bit_counter <= bit_counter + 1'b1;
                            end
                        end else begin
                            tick_counter <= tick_counter + 1'b1;
                        end
                    end
                    
                    PARITY_BIT: begin
                        if (tick_counter == 4'd15) begin
                            parity_bit_received <= rx_sync;
                            state <= STOP_BIT;
                            tick_counter <= 4'd0;
                        end else begin
                            tick_counter <= tick_counter + 1'b1;
                        end
                    end
                    
                    STOP_BIT: begin
                        if (tick_counter == 4'd15) begin
                            if (rx_sync) begin // Valid stop bit
                                data_out <= rx_data_reg;
                                rx_ready <= 1'b1;
                                frame_error <= 1'b0;
                                if (PARITY_EN != 0)
                                    parity_error <= (parity_bit_received != parity_calculated);
                                else
                                    parity_error <= 1'b0;
                            end else begin // Framing error
                                frame_error <= 1'b1;
                            end
                            state <= IDLE;
                        end else begin
                            tick_counter <= tick_counter + 1'b1;
                        end
                    end
                    
                    default: state <= IDLE;
                endcase
            end
        end
    end

endmodule