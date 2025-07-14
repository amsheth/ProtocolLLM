/**
 * @brief A configurable full-duplex UART Controller.
 *
 * This module implements a standard UART for serial communication. It includes
 * independent transmitter and receiver blocks.
 *
 * @param SYS_CLK_FREQ  System clock frequency in Hz (e.g., 50_000_000 for 50 MHz).
 * @param BAUD_RATE     Desired baud rate in bits per second (e.g., 9600).
 * @param PARITY_EN     Enable parity bit generation and checking (1 for enabled, 0 for disabled).
 *                      Parity is Even Parity.
 * @param STOP_BITS     Number of stop bits (supports 1 or 2).
 */
module UART_driver #(
    parameter int SYS_CLK_FREQ  = 50_000_000, // 50 MHz system clock
    parameter int BAUD_RATE     = 9600,
    parameter bit PARITY_EN     = 0,          // 0: No Parity, 1: Even Parity
    parameter int STOP_BITS     = 1
) (
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset (active high)
    // Transmitter Interface
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    output logic       TX,         // UART transmit line
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    // Receiver Interface
    input  logic       RX,         // UART receive line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Error  // High if framing or parity error detected
);

    //--------------------------------------------------------------------------
    // Internal Parameters and Types
    //--------------------------------------------------------------------------
    localparam int BAUD_DIVISOR = SYS_CLK_FREQ / BAUD_RATE;

    // Transmitter FSM states
    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START_BIT,
        TX_DATA_BITS,
        TX_PARITY_BIT,
        TX_STOP_BIT
    } tx_state_e;

    // Receiver FSM states
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_START_BIT,
        RX_DATA_BITS,
        RX_PARITY_BIT,
        RX_STOP_BIT,
        RX_CLEANUP
    } rx_state_e;

    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    // Baud tick generator
    logic       baud_tick;
    int         baud_counter;

    // Transmitter signals
    tx_state_e  tx_state, tx_next_state;
    logic [7:0] tx_data_reg;
    logic       tx_parity_reg;
    logic [2:0] tx_bit_count;
    logic       tx_reg;

    // Receiver signals
    logic       rx_sync_q1, rx_sync_q2; // 2-flop synchronizer for RX input
    rx_state_e  rx_state, rx_next_state;
    logic [7:0] rx_data_reg;
    logic       rx_parity_reg;
    logic [2:0] rx_bit_count;
    logic       framing_error;
    logic       parity_error;

    //--------------------------------------------------------------------------
    // Baud Rate Tick Generator
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_counter <= 0;
        end else begin
            if (baud_counter >= BAUD_DIVISOR - 1) begin
                baud_counter <= 0;
            end else begin
                baud_counter <= baud_counter + 1;
            end
        end
    end
    assign baud_tick = (baud_counter == (BAUD_DIVISOR / 2)); // Tick in middle of bit time

    //--------------------------------------------------------------------------
    // Transmitter Logic
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            tx_data_reg <= '0;
            tx_parity_reg <= '0;
            tx_bit_count <= '0;
            tx_reg <= 1'b1; // TX idle state is high
        end else begin
            tx_state <= tx_next_state;
            if (tx_next_state != tx_state) begin // Reset counter on state change
                tx_bit_count <= '0;
            end

            case (tx_state)
                TX_IDLE: begin
                    tx_reg <= 1'b1;
                    if (UART_Start) begin
                        tx_data_reg <= data_in;
                        if (PARITY_EN) begin
                           tx_parity_reg <= ^data_in; // XOR reduction for even parity
                        end
                    end
                end
                TX_START_BIT: begin
                    if (baud_tick) begin
                        tx_reg <= 1'b0; // Start bit is low
                    end
                end
                TX_DATA_BITS: begin
                    if (baud_tick) begin
                        tx_reg <= tx_data_reg[tx_bit_count];
                        tx_bit_count <= tx_bit_count + 1;
                    end
                end
                TX_PARITY_BIT: begin
                    if (baud_tick) begin
                        tx_reg <= tx_parity_reg;
                    end
                end
                TX_STOP_BIT: begin
                    if (baud_tick) begin
                        tx_reg <= 1'b1; // Stop bit is high
                        tx_bit_count <= tx_bit_count + 1;
                    end
                end
            endcase
        end
    end

    // Transmitter FSM next-state logic
    always_comb begin
        tx_next_state = tx_state;
        case (tx_state)
            TX_IDLE: begin
                if (UART_Start) begin
                    tx_next_state = TX_START_BIT;
                end
            end
            TX_START_BIT: begin
                if (baud_tick) begin
                    tx_next_state = TX_DATA_BITS;
                end
            end
            TX_DATA_BITS: begin
                if (baud_tick && (tx_bit_count == 7)) begin
                    tx_next_state = PARITY_EN ? TX_PARITY_BIT : TX_STOP_BIT;
                end
            end
            TX_PARITY_BIT: begin
                if (baud_tick) begin
                    tx_next_state = TX_STOP_BIT;
                end
            end
            TX_STOP_BIT: begin
                if (baud_tick && (tx_bit_count >= STOP_BITS - 1)) begin
                    tx_next_state = TX_IDLE;
                end
            end
        endcase
    end

    // Combinational outputs for transmitter
    assign TX = tx_reg;
    assign UART_Ready = (tx_state == TX_IDLE);
    assign UART_Busy = (tx_state != TX_IDLE);

    //--------------------------------------------------------------------------
    // Receiver Logic
    //--------------------------------------------------------------------------
    // Synchronize asynchronous RX input to system clock domain
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync_q1 <= 1'b1;
            rx_sync_q2 <= 1'b1;
        end else begin
            rx_sync_q1 <= RX;
            rx_sync_q2 <= rx_sync_q1;
        end
    end

    // Receiver FSM state and data logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state      <= RX_IDLE;
            rx_data_reg   <= '0;
            rx_bit_count  <= '0;
            data_out      <= '0;
            framing_error <= 1'b0;
            parity_error  <= 1'b0;
        end else begin
            rx_state <= rx_next_state;
            if (rx_next_state != rx_state) begin // Reset counter on state change
                rx_bit_count <= '0;
            end

            case (rx_state)
                RX_START_BIT: begin
                    if (baud_tick) begin
                        if (rx_sync_q2 == 1'b0) begin // Valid start bit
                            // Bit is valid, proceed
                        end else begin
                            // Glitch detected, go back to idle
                        end
                    end
                end
                RX_DATA_BITS: begin
                    if (baud_tick) begin
                        rx_data_reg[rx_bit_count] <= rx_sync_q2;
                        rx_bit_count <= rx_bit_count + 1;
                    end
                end
                RX_PARITY_BIT: begin
                    if (baud_tick) begin
                        rx_parity_reg <= rx_sync_q2;
                    end
                end
                RX_STOP_BIT: begin
                    if (baud_tick) begin
                        // Check for framing error (stop bit must be high)
                        if (rx_sync_q2 == 1'b0) begin
                            framing_error <= 1'b1;
                        end
                        // Check for parity error
                        if (PARITY_EN && (^rx_data_reg != rx_parity_reg)) begin
                            parity_error <= 1'b1;
                        end
                        rx_bit_count <= rx_bit_count + 1;
                    end
                end
                RX_CLEANUP: begin
                    data_out <= rx_data_reg;
                    framing_error <= 1'b0;
                    parity_error <= 1'b0;
                end
                default: begin // RX_IDLE
                    framing_error <= 1'b0;
                    parity_error <= 1'b0;
                end
            endcase
        end
    end

    // Receiver FSM next-state logic
    always_comb begin
        rx_next_state = rx_state;
        case (rx_state)
            RX_IDLE: begin
                // Detect start bit (falling edge)
                if (rx_sync_q2 == 1'b0) begin
                    rx_next_state = RX_START_BIT;
                end
            end
            RX_START_BIT: begin
                if (baud_tick) begin
                    if (rx_sync_q2 == 1'b0) begin // Valid start bit
                        rx_next_state = RX_DATA_BITS;
                    end else begin // Glitch
                        rx_next_state = RX_IDLE;
                    end
                end
            end
            RX_DATA_BITS: begin
                if (baud_tick && (rx_bit_count == 7)) begin
                    rx_next_state = PARITY_EN ? RX_PARITY_BIT : RX_STOP_BIT;
                end
            end
            RX_PARITY_BIT: begin
                if (baud_tick) begin
                    rx_next_state = RX_STOP_BIT;
                end
            end
            RX_STOP_BIT: begin
                if (baud_tick && (rx_bit_count >= STOP_BITS - 1)) begin
                    rx_next_state = RX_CLEANUP;
                end
            end
            RX_CLEANUP: begin
                rx_next_state = RX_IDLE;
            end
        endcase
    end

    // Final error output
    assign UART_Error = framing_error || parity_error;

endmodule