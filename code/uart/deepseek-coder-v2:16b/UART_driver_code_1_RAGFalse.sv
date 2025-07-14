module UART_driver(
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [8:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line input
    output logic       TX,         // UART transmit line output
    output logic [8:0] data_out,   // Received data output
    output logic       UART_Ready, // Ready to transmit next byte output
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Define parameters for baud rate configuration (example: 9600 baud)
    parameter int BAUD_RATE = 9600;
    parameter int CLK_FREQ = 50000000; // Clock frequency in Hz

    // Calculate the number of clock cycles per bit
    localparam int CYCLES_PER_BIT = CLK_FREQ / BAUD_RATE;

    // State machine for transmitting data
    enum logic {IDLE, START, DATA, PARITY, STOP1, STOP2} state_tx;
    logic [3:0] bit_index_tx;
    logic tx_start;
    logic [8:0] shift_reg_tx;
    logic baud_tick;

    // State machine for receiving data
    enum logic {IDLE_RX, START_RX, DATA_RX, PARITY_RX, STOP1_RX, STOP2_RX} state_rx;
    logic [3:0] bit_index_rx;
    logic rx_sample;
    logic [8:0] shift_reg_rx;

    // Baud rate generator
    logic [15:0] baud_counter;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_counter <= 0;
            baud_tick <= 0;
        end else begin
            if (baud_counter >= CYCLES_PER_BIT - 1) begin
                baud_counter <= 0;
                baud_tick <= 1;
            end else begin
                baud_counter <= baud_counter + 1;
                baud_tick <= 0;
            end
        end
    end

    // Transmit state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_tx <= IDLE;
            bit_index_tx <= 0;
            shift_reg_tx <= 0;
            TX <= 1;
            UART_Busy <= 0;
        end else begin
            case (state_tx)
                IDLE: begin
                    if (UART_Start) begin
                        state_tx <= START;
                        shift_reg_tx <= data_in;
                        UART_Busy <= 1;
                    end
                end
                START: begin
                    TX <= 0;
                    if (baud_tick) begin
                        state_tx <= DATA;
                        bit_index_tx <= 0;
                    end
                end
                DATA: begin
                    if (baud_tick) begin
                        if (bit_index_tx == 8) begin
                            state_tx <= PARITY;
                        end else begin
                            TX <= shift_reg_tx[0];
                            shift_reg_tx <= {1'b0, shift_reg_tx[8:1]};
                            bit_index_tx <= bit_index_tx + 1;
                        end
                    end
                end
                PARITY: begin
                    if (baud_tick) begin
                        TX <= ^shift_reg_tx; // Calculate parity and transmit it
                        state_tx <= STOP1;
                    end
                end
                STOP1: begin
                    if (baud_tick) begin
                        TX <= 1;
                        state_tx <= STOP2;
                    end
                end
                STOP2: begin
                    if (baud_tick) begin
                        UART_Busy <= 0;
                        state_tx <= IDLE;
                        UART_Ready <= 1;
                    end
                end
            endcase
        end
    end

    // Receive state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_rx <= IDLE_RX;
            bit_index_rx <= 0;
            shift_reg_rx <= 0;
            RX <= 1;
        end else begin
            case (state_rx)
                IDLE_RX: begin
                    if (!RX) begin
                        state_rx <= START_RX;
                        bit_index_rx <= 0;
                    end
                end
                START_RX: begin
                    if (baud_tick) begin
                        if (bit_index_rx == 15) begin // Wait for two stop bits to ensure proper start
                            state_rx <= DATA_RX;
                            bit_index_rx <= 0;
                        end else begin
                            bit_index_rx <= bit_index_rx + 1;
                        end
                    end
                end
                DATA_RX: begin
                    if (baud_tick) begin
                        if (bit_index_rx == 9) begin // Receive all bits including parity and stop bits
                            state_rx <= STOP1_RX;
                            shift_reg_rx <= {RX, shift_reg_rx[8:1]};
                            bit_index_rx <= 0;
                        end else begin
                            RX <= 1;
                            if (bit_index_rx == 7) begin // Adjust for parity bit
                                if (!(&shift_reg_rx[8:1])) begin // Parity error
                                    UART_Error <= 1;
                                end
                            end
                            shift_reg_rx <= {RX, shift_reg_rx[8:1]};
                            bit_index_rx <= bit_index_rx + 1;
                        end
                    end
                end
                STOP1_RX: begin
                    if (baud_tick) begin
                        state_rx <= STOP2_RX;
                        bit_index_rx <= 0;
                    end
                end
                STOP2_RX: begin
                    if (baud_tick) begin
                        data_out <= shift_reg_rx;
                        UART_Ready <= 1;
                        state_rx <= IDLE_RX;
                    end
                end
            endcase
        end
    end
endmodule