module UART_driver(
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

    parameter BAUD_RATE    = 9600;     // Baud rate parameter
    parameter CLOCK_FREQ   = 50000000; // System clock frequency in Hz
    parameter DATA_BITS    = 8;
    parameter PARITY_ENABLE = 0;       // Set to 1 to enable parity
    parameter PARITY_ODD   = 0;       // Set to 1 for odd parity, 0 for even parity

    localparam integer CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;

    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        PARITY,
        STOP
    } state_t;

    logic [DATA_BITS-1:0] tx_shift_reg;
    logic [DATA_BITS-1:0] rx_shift_reg;
    logic [3:0] bit_count;
    logic [15:0] clk_count;
    state_t tx_state, rx_state;
    logic parity_bit;

    // Transmitter logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_state <= IDLE;
            TX <= 1'b1;
            UART_Busy <= 1'b0;
            bit_count <= 4'b0;
            clk_count <= 16'b0;
            tx_shift_reg <= 8'b0;
        end else begin
            case (tx_state)
                IDLE: begin
                    UART_Busy <= 1'b0;
                    if (UART_Start) begin
                        tx_state <= START;
                        tx_shift_reg <= data_in;
                        parity_bit <= ^data_in ^ PARITY_ODD;
                        clk_count <= 16'b0;
                        bit_count <= 4'b0;
                    end
                end
                START: begin
                    TX <= 1'b0; // Start bit
                    UART_Busy <= 1'b1;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        tx_state <= DATA;
                        clk_count <= 16'b0;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                DATA: begin
                    TX <= tx_shift_reg[0];
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        tx_shift_reg <= tx_shift_reg >> 1;
                        bit_count <= bit_count + 1;
                        if (bit_count == DATA_BITS-1) begin
                            if (PARITY_ENABLE) begin
                                tx_state <= PARITY;
                            end else begin
                                tx_state <= STOP;
                            end
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                PARITY: begin
                    TX <= parity_bit;
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 16'b0;
                        tx_state <= STOP;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                STOP: begin
                    TX <= 1'b1; // Stop bit
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        tx_state <= IDLE;
                        UART_Ready <= 1'b1;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                default: tx_state <= IDLE;
            endcase
        end
    end

    // Receiver logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_state <= IDLE;
            data_out <= 8'b0;
            bit_count <= 4'b0;
            clk_count <= 16'b0;
            UART_Error <= 1'b0;
        end else begin
            case (rx_state)
                IDLE: begin
                    if (!RX) begin // Detect start bit
                        rx_state <= START;
                        clk_count <= 16'b0;
                    end
                end
                START: begin
                    if (clk_count == CLKS_PER_BIT-1) begin
                        if (!RX) begin
                            rx_state <= DATA;
                            clk_count <= 16'b0;
                            bit_count <= 4'b0;
                        end else begin
                            rx_state <= IDLE; // False start
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                DATA: begin
                    if (clk_count == CLKS_PER_BIT/2 - 1) begin
                        rx_shift_reg[bit_count] <= RX;
                        clk_count <= 16'b0;
                        bit_count <= bit_count + 1;
                        if (bit_count == DATA_BITS-1) begin
                            if (PARITY_ENABLE) begin
                                rx_state <= PARITY;
                            end else begin
                                rx_state <= STOP;
                            end
                        end
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                PARITY: begin
                    if (clk_count == CLKS_PER_BIT-1) begin
                        // Check parity
                        parity_bit <= ^rx_shift_reg ^ PARITY_ODD;
                        if (parity_bit != RX) begin
                            UART_Error <= 1'b1;
                        end
                        rx_state <= STOP;
                        clk_count <= 16'b0;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                STOP: begin
                    if (clk_count == CLKS_PER_BIT-1) begin
                        if (RX) begin
                            data_out <= rx_shift_reg;
                        end else begin
                            UART_Error <= 1'b1; // Framing error
                        end
                        rx_state <= IDLE;
                    end else begin
                        clk_count <= clk_count + 1;
                    end
                end
                default: rx_state <= IDLE;
            endcase
        end
    end
endmodule