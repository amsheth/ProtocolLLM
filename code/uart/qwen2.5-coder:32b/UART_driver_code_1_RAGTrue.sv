module UART_driver(
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,   // Data to be transmitted (8-bit)
    output logic       TX,         // UART transmit line
    input  logic       RX,         // UART receive line
    output logic [7:0] data_out,  // Received data (8-bit)
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    parameter BAUD_RATE = 9600;   // Baud rate (default: 9600)
    localparam CLK_FREQ = 50_000_000; // System clock frequency in Hz

    logic [15:0] baud_divisor;
    assign baud_divisor = CLK_FREQ / BAUD_RATE;

    // TX Logic
    typedef enum logic [2:0] {IDLE, START, DATA, STOP} tx_state_t;
    tx_state_t tx_state, next_tx_state;
    logic [3:0] bit_cnt;
    logic [7:0] shift_reg;
    logic       tx_busy;

    // RX Logic
    typedef enum logic [2:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t rx_state, next_rx_state;
    logic [3:0] rx_bit_cnt;
    logic [7:0] rx_shift_reg;
    logic       rx_busy;

    // Baud rate generation
    logic [15:0] baud_counter;
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            baud_counter <= 0;
        else if (baud_counter == baud_divisor - 1)
            baud_counter <= 0;
        else
            baud_counter <= baud_counter + 1;
    end

    // TX State Machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            tx_state <= IDLE;
        else
            tx_state <= next_tx_state;
    end

    always_comb begin
        next_tx_state = tx_state;
        case (tx_state)
            IDLE: begin
                if (UART_Start && !tx_busy) begin
                    next_tx_state = START;
                    shift_reg = {1'b0, data_in}; // Start bit is 0
                    bit_cnt = 8; // 8 data bits to send
                    tx_busy = 1;
                end
            end
            START: begin
                if (baud_counter == baud_divisor - 1) begin
                    next_tx_state = DATA;
                end
            end
            DATA: begin
                if (baud_counter == baud_divisor - 1) begin
                    bit_cnt = bit_cnt - 1;
                    shift_reg = {shift_reg[6:0], 1'b1}; // Shift out the MSB and add a stop bit
                    if (bit_cnt == 0)
                        next_tx_state = STOP;
                end
            end
            STOP: begin
                if (baud_counter == baud_divisor - 1) begin
                    tx_busy = 0;
                    next_tx_state = IDLE;
                end
            end
        endcase
    end

    // TX Output Logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            TX <= 1'b1; // Idle state is high
        else if (tx_state == START || tx_state == DATA)
            TX <= shift_reg[7];
        else if (tx_state == STOP)
            TX <= 1'b1;
    end

    assign UART_Ready = !tx_busy;

    // RX State Machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            rx_state <= RX_IDLE;
        else
            rx_state <= next_rx_state;
    end

    always_comb begin
        next_rx_state = rx_state;
        case (rx_state)
            RX_IDLE: begin
                if (!RX) begin // Start bit detected
                    next_rx_state = RX_START;
                    rx_bit_cnt = 8; // 8 data bits to receive
                    rx_shift_reg = 0;
                end
            end
            RX_START: begin
                if (baud_counter == baud_divisor / 2 - 1) begin // Sample in the middle of the start bit
                    next_rx_state = RX_DATA;
                end
            end
            RX_DATA: begin
                if (baud_counter == baud_divisor - 1) begin
                    rx_bit_cnt = rx_bit_cnt - 1;
                    rx_shift_reg = {RX, rx_shift_reg[7:1]};
                    if (rx_bit_cnt == 0)
                        next_rx_state = RX_STOP;
                end
            end
            RX_STOP: begin
                if (baud_counter == baud_divisor / 2 - 1) begin // Sample in the middle of the stop bit
                    if (RX != 1'b1) // Check for valid stop bit
                        UART_Error <= 1'b1;
                    else
                        data_out <= rx_shift_reg;
                    next_rx_state = RX_IDLE;
                end
            end
        endcase
    end

    assign UART_Busy = tx_busy || rx_busy;

endmodule