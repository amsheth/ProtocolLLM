module UART_driver(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [8:0] data_in,    // Data to be transmitted (9 bits for parity)
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [8:0] data_out,   // Received data (9 bits for parity)
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

parameter BAUD_RATE = 9600; // Baud rate in bits per second
parameter CLK_FREQ = 50_000_000; // System clock frequency in Hz

// Calculate the number of clock cycles for one bit time
localparam BIT_TIME = CLK_FREQ / BAUD_RATE;

// State encoding
typedef enum logic [2:0] {
    IDLE,
    START_BIT,
    DATA_BITS,
    PARITY_BIT,
    STOP_BITS,
    ERROR
} state_t;

state_t state, next_state;
logic [3:0] bit_count;
logic [8:0] shift_reg_tx;
logic [8:0] shift_reg_rx;
logic parity_enable;
logic parity_bit;
logic framing_error;
logic parity_error;

// State machine for transmission
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        state <= IDLE;
    else
        state <= next_state;
end

always_comb begin
    next_state = state;
    UART_Ready = 1'b0;
    UART_Busy = 1'b0;
    TX = 1'b1; // Default to idle high
    framing_error = 1'b0;
    parity_error = 1'b0;

    case (state)
        IDLE: begin
            if (UART_Start) begin
                next_state = START_BIT;
                UART_Busy = 1'b1;
                shift_reg_tx <= data_in;
                bit_count <= 4'd9; // Start with the start bit
            end else begin
                UART_Ready = 1'b1;
            end
        end

        START_BIT: begin
            TX = 1'b0;
            if (bit_count == 4'd0) begin
                next_state = DATA_BITS;
                bit_count <= 4'd8; // Start with the first data bit
            end else begin
                bit_count <= bit_count - 1;
            end
        end

        DATA_BITS: begin
            TX = shift_reg_tx[bit_count];
            if (bit_count == 4'd0) begin
                if (parity_enable)
                    next_state = PARITY_BIT;
                else
                    next_state = STOP_BITS;
            end else begin
                bit_count <= bit_count - 1;
            end
        end

        PARITY_BIT: begin
            TX = parity_bit;
            next_state = STOP_BITS;
        end

        STOP_BITS: begin
            if (bit_count == 4'd0) begin
                next_state = IDLE;
            end else begin
                bit_count <= bit_count - 1;
            end
        end

        ERROR: begin
            // Handle error state
            next_state = IDLE;
        end
    endcase
end

// Parity calculation
always_comb begin
    parity_bit = 1'b0;
    for (int i = 0; i < 8; i++)
        parity_bit ^= data_in[i];
end

// State machine for reception
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        shift_reg_rx <= 9'd0;
        bit_count <= 4'd0;
        framing_error <= 1'b0;
        parity_error <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                if (!RX) begin
                    next_state = START_BIT;
                    shift_reg_rx[8] <= RX; // Capture start bit
                end
            end

            START_BIT: begin
                if (bit_count == 4'd0) begin
                    next_state = DATA_BITS;
                    bit_count <= 4'd8;
                end else begin
                    bit_count <= bit_count - 1;
                end
            end

            DATA_BITS: begin
                shift_reg_rx[7:0] <= {shift_reg_rx[6:0], RX};
                if (bit_count == 4'd0) begin
                    if (parity_enable)
                        next_state = PARITY_BIT;
                    else
                        next_state = STOP_BITS;
                end else begin
                    bit_count <= bit_count - 1;
                end
            end

            PARITY_BIT: begin
                parity_error <= RX != parity_bit;
                next_state = STOP_BITS;
            end

            STOP_BITS: begin
                if (bit_count == 4'd0) begin
                    data_out <= shift_reg_rx;
                    UART_Error <= framing_error | parity_error;
                    next_state = IDLE;
                end else begin
                    bit_count <= bit_count - 1;
                end
            end

            ERROR: begin
                // Handle error state
                next_state = IDLE;
            end
        endcase
    end
end

// Error detection
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        framing_error <= 1'b0;
    else if (state == START_BIT && RX != 1'b0)
        framing_error <= 1'b1;
end

endmodule