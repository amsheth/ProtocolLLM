module UART_driver #(
    parameter int BAUD_RATE = 9600, // Baud rate
    parameter int CLK_FREQ = 50_000_000, // System clock frequency
    parameter bit USE_PARITY = 0 // Set to 1 to enable parity bit
)(
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Internal signals
    logic [15:0] baud_divisor;
    logic [3:0] bit_counter;
    logic [7:0] tx_buffer;
    logic [7:0] rx_buffer;
    logic tx_start;
    logic rx_start;
    logic tx_done;
    logic rx_done;
    logic parity_bit;
    logic parity_error;
    logic framing_error;

    // Baud rate divisor calculation
    assign baud_divisor = (CLK_FREQ / BAUD_RATE) / 2;

    // UART transmitter
    UART_TX #(
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ(CLK_FREQ),
        .USE_PARITY(USE_PARITY)
    ) uart_tx (
        .clk(clk),
        .rst(rst),
        .start(tx_start),
        .data_in(tx_buffer),
        .tx(TX),
        .done(tx_done),
        .busy(UART_Busy)
    );

    // UART receiver
    UART_RX #(
        .BAUD_RATE(BAUD_RATE),
        .CLK_FREQ(CLK_FREQ),
        .USE_PARITY(USE_PARITY)
    ) uart_rx (
        .clk(clk),
        .rst(rst),
        .rx(RX),
        .data_out(rx_buffer),
        .parity_error(parity_error),
        .framing_error(framing_error),
        .done(rx_done)
    );

    // Transmit control logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_start <= 0;
            UART_Ready <= 1;
        end else begin
            if (UART_Start && UART_Ready) begin
                tx_start <= 1;
                tx_buffer <= data_in;
                UART_Ready <= 0;
            end else if (tx_done) begin
                tx_start <= 0;
                UART_Ready <= 1;
            end
        end
    end

    // Receive control logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 0;
            UART_Error <= 0;
        end else begin
            if (rx_done) begin
                data_out <= rx_buffer;
                UART_Error <= parity_error || framing_error;
            end
        end
    end

endmodule

// UART_TX module
module UART_TX #(
    parameter int BAUD_RATE = 9600,
    parameter int CLK_FREQ = 50_000_000,
    parameter bit USE_PARITY = 0
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       start,
    input  logic [7:0] data_in,
    output logic       tx,
    output logic       done,
    output logic       busy
);

    // Internal signals
    logic [15:0] baud_counter;
    logic [3:0] bit_counter;
    logic [8:0] tx_shift_reg;
    logic parity_bit;

    // Parity bit calculation
    assign parity_bit = USE_PARITY ? ^data_in : 1'b0;

    // Transmit state machine
    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        PARITY,
        STOP
    } tx_state_t;

    tx_state_t state, next_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            baud_counter <= 0;
            bit_counter <= 0;
            tx_shift_reg <= 0;
            tx <= 1;
            done <= 0;
            busy <= 0;
        end else begin
            state <= next_state;
            done <= 0;
            case (state)
                IDLE: begin
                    if (start) begin
                        baud_counter <= baud_divisor;
                        bit_counter <= 0;
                        tx_shift_reg <= {parity_bit, data_in, 1'b0}; // Start bit is 0
                        tx <= 0;
                        busy <= 1;
                    end
                end
                START: begin
                    if (baud_counter == 0) begin
                        baud_counter <= baud_divisor;
                        bit_counter <= bit_counter + 1;
                        tx <= tx_shift_reg[0];
                        tx_shift_reg <= tx_shift_reg >> 1;
                    end else begin
                        baud_counter <= baud_counter - 1;
                    end
                end
                DATA: begin
                    if (baud_counter == 0) begin
                        baud_counter <= baud_divisor;
                        bit_counter <= bit_counter + 1;
                        tx <= tx_shift_reg[0];
                        tx_shift_reg <= tx_shift_reg >> 1;
                        if (bit_counter == 7) begin
                            next_state <= USE_PARITY ? PARITY : STOP;
                        end
                    end else begin
                        baud_counter <= baud_counter - 1;
                    end
                end
                PARITY: begin
                    if (baud_counter == 0) begin
                        baud_counter <= baud_divisor;
                        tx <= parity_bit;
                        next_state <= STOP;
                    end else begin
                        baud_counter <= baud_counter - 1;
                    end
                end
                STOP: begin
                    if (baud_counter == 0) begin
                        baud_counter <= baud_divisor;
                        tx <= 1;
                        done <= 1;
                        busy <= 0;
                        next_state <= IDLE;
                    end else begin
                        baud_counter <= baud_counter - 1;
                    end
                end
            endcase
        end
    end

endmodule

// UART_RX module
module UART_RX #(
    parameter int BAUD_RATE = 9600,
    parameter int CLK_FREQ = 50_000_000,
    parameter bit USE_PARITY = 0
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,
    output logic [7:0] data_out,
    output logic       parity_error,
    output logic       framing_error,
    output logic       done
);

    // Internal signals
    logic [15:0] baud_counter;
    logic [3:0] bit_counter;
    logic [8:0] rx_shift_reg;
    logic expected_parity;

    // Receive state machine
    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        PARITY,
        STOP
    } rx_state_t;

    rx_state_t state, next_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            baud_counter <= 0;
            bit_counter <= 0;
            rx_shift_reg <= 0;
            data_out <= 0;
            parity_error <= 0;
            framing_error <= 0;
            done <= 0;
        end else begin
            state <= next_state;
            done <= 0;
            case (state)
                IDLE: begin
                    if (rx == 0) begin // Start bit detection
                        baud_counter <= baud_divisor;
                        bit_counter <= 0;
                        rx_shift_reg <= 0;
                        next_state <= START;
                    end
                end
                START: begin
                    if (baud_counter == 0) begin
                        baud_counter <= baud_divisor;
                        if (rx == 0) begin // Confirm start bit
                            next_state <= DATA;
                        end else begin
                            next_state <= IDLE;
                        end
                    end else begin
                        baud_counter <= baud_counter - 1;
                    end
                end
                DATA: begin
                    if (baud_counter == 0) begin
                        baud_counter <= baud_divisor;
                        bit_counter <= bit_counter + 1;
                        rx_shift_reg <= {rx, rx_shift_reg[8:1]};
                        if (bit_counter == 7) begin
                            next_state <= USE_PARITY ? PARITY : STOP;
                        end
                    end else begin
                        baud_counter <= baud_counter - 1;
                    end
                end
                PARITY: begin
                    if (baud_counter == 0) begin
                        baud_counter <= baud_divisor;
                        expected_parity <= ^rx_shift_reg[7:0];
                        if (rx != expected_parity) begin
                            parity_error <= 1;
                        end
                        next_state <= STOP;
                    end else begin
                        baud_counter <= baud_counter - 1;
                    end
                end
                STOP: begin
                    if (baud_counter == 0) begin
                        baud_counter <= baud_divisor;
                        if (rx == 1) begin // Confirm stop bit
                            data_out <= rx_shift_reg[7:0];
                            done <= 1;
                        end else begin
                            framing_error <= 1;
                        end
                        next_state <= IDLE;
                    end else begin
                        baud_counter <= baud_counter - 1;
                    end
                end
            endcase
        end
    end

endmodule