module UART_driver(
    input  logic       clk,        // System clock input
    input  logic       rst,        // Asynchronous reset input
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [7:0] data_in,   // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [7:0] data_out,  // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing error detected
);

    parameter CLK_FREQ = 50_000_000; // System clock frequency in Hz
    parameter BAUD_RATE = 9600;      // Desired baud rate

    localparam DIVISOR = CLK_FREQ / (BAUD_RATE * 16); // Baud rate divisor for 16x oversampling

    logic [3:0] tx_bit_cnt;
    logic [3:0] rx_bit_cnt;

    logic [7:0] tx_data_reg;
    logic       tx_start_reg;
    logic       tx_busy_reg;
    logic       tx_done;

    logic [7:0] rx_data_reg;
    logic       rx_start;
    logic       rx_busy;
    logic       rx_error;

    // Baud rate generator
    logic [$clog2(DIVISOR)-1:0] baud_cnt;
    logic clk_16x;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            baud_cnt <= '0;
            clk_16x  <= '0;
        end else begin
            if (baud_cnt == DIVISOR - 1) begin
                baud_cnt <= '0;
                clk_16x  <= ~clk_16x;
            end else begin
                baud_cnt <= baud_cnt + 1'b1;
            end
        end
    end

    // Transmitter logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_bit_cnt   <= '0;
            tx_data_reg  <= '0;
            tx_start_reg <= '0;
            tx_busy_reg  <= '0;
            TX           <= 1'b1; // Idle high
        end else begin
            if (UART_Start && !tx_busy_reg) begin
                tx_bit_cnt   <= '0;
                tx_data_reg  <= data_in;
                tx_start_reg <= 1'b1;
                tx_busy_reg  <= 1'b1;
                TX           <= 1'b0; // Start bit
            end else if (clk_16x && tx_busy_reg) begin
                case (tx_bit_cnt)
                    4'd0: TX <= tx_data_reg[0];
                    4'd1: TX <= tx_data_reg[1];
                    4'd2: TX <= tx_data_reg[2];
                    4'd3: TX <= tx_data_reg[3];
                    4'd4: TX <= tx_data_reg[4];
                    4'd5: TX <= tx_data_reg[5];
                    4'd6: TX <= tx_data_reg[6];
                    4'd7: TX <= tx_data_reg[7];
                    4'd8: TX <= 1'b1; // Stop bit
                endcase

                if (tx_bit_cnt == 4'd9) begin
                    tx_busy_reg <= '0;
                    tx_done     <= '1;
                end else begin
                    tx_bit_cnt <= tx_bit_cnt + 1'b1;
                end
            end else begin
                tx_start_reg <= '0;
                tx_done      <= '0;
            end
        end
    end

    // Receiver logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_bit_cnt  <= '0;
            rx_data_reg <= '0;
            rx_start    <= '0;
            rx_busy     <= '0;
            data_out    <= '0;
            UART_Error  <= '0;
        end else begin
            // Detect start bit
            if (!RX && !rx_busy) begin
                rx_bit_cnt <= '0;
                rx_data_reg <= '0;
                rx_start   <= '1;
                rx_busy    <= '1;
                UART_Error <= '0;
            end else if (clk_16x && rx_busy) begin
                case (rx_bit_cnt)
                    4'd0: rx_data_reg[0] <= RX;
                    4'd1: rx_data_reg[1] <= RX;
                    4'd2: rx_data_reg[2] <= RX;
                    4'd3: rx_data_reg[3] <= RX;
                    4'd4: rx_data_reg[4] <= RX;
                    4'd5: rx_data_reg[5] <= RX;
                    4'd6: rx_data_reg[6] <= RX;
                    4'd7: rx_data_reg[7] <= RX;
                endcase

                if (rx_bit_cnt == 4'd8) begin
                    // Check stop bit
                    if (RX != 1'b1)
                        UART_Error <= '1;

                    data_out <= rx_data_reg;
                    rx_busy  <= '0;
                end else begin
                    rx_bit_cnt <= rx_bit_cnt + 1'b1;
                end
            end else begin
                rx_start <= '0;
            end
        end
    end

    // Outputs
    assign UART_Ready = !tx_busy_reg;
    assign UART_Busy  = tx_busy_reg;

endmodule