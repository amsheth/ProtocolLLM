module UART_driver(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       UART_Start, // Signal to initiate transmission
    input  logic [8:0] data_in,    // Data to be transmitted
    input  logic       RX,         // UART receive line
    output logic       TX,         // UART transmit line
    output logic [8:0] data_out,   // Received data
    output logic       UART_Ready, // Ready to transmit next byte
    output logic       UART_Busy,  // Indicates UART is currently transmitting
    output logic       UART_Error  // High if framing or parity error detected
);

    // Parameters
    parameter BAUD_RATE = 9600;
    parameter CLOCK_FREQ = 50000000;
    
    // Internal variables
    logic [3:0] bit_cnt;           // Bit counter for data bits
    logic [13:0] clk_div_cnt;      // Clock divider counter for generating baud rate
    logic        sending;          // Transaction in progress flag
    logic [9:0]  tx_shift_reg;     // TX shift register
    logic [9:0]  rx_shift_reg;     // RX shift register
    logic [3:0]  rx_bit_cnt;       // RX bit counter
    logic        rx_sample;        // Sample RX line
    
    // Calculate clock divisor
    localparam integer CLK_DIV = CLOCK_FREQ / (BAUD_RATE * 16);

    // Initial assignments
    initial begin
        UART_Ready = 1'b1;
        UART_Busy  = 1'b0;
        UART_Error = 1'b0;
        TX         = 1'b1;        // Idle state
    end

    // TX Process
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt      <= 4'b0;
            clk_div_cnt  <= 14'b0;
            sending      <= 1'b0;
            UART_Busy    <= 1'b0;
            UART_Ready   <= 1'b1;
            TX           <= 1'b1;
            tx_shift_reg <= 10'b1111111111;
        end else begin
            if (UART_Start && !sending) begin
                // Load data into shift register with start and stop bits
                tx_shift_reg <= {1'b1, data_in, 1'b0};
                sending      <= 1'b1;
                UART_Ready   <= 1'b0;
                UART_Busy    <= 1'b1;
                bit_cnt      <= 4'b0;
            end

            if (sending) begin
                if (clk_div_cnt < CLK_DIV - 1) begin
                    clk_div_cnt <= clk_div_cnt + 1'b1;
                end else begin
                    clk_div_cnt <= 14'b0;
                    TX          <= tx_shift_reg[0];  // Output the current bit
                    tx_shift_reg <= {1'b1, tx_shift_reg[9:1]}; // Shift the register

                    if (bit_cnt == 4'd10) begin // End of transmission
                        sending    <= 1'b0;
                        UART_Ready <= 1'b1;
                        UART_Busy  <= 1'b0;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
            end
        end
    end

    // RX Process
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_bit_cnt <= 4'b0;
            clk_div_cnt <= 14'b0;
            rx_sample   <= 1'b1;
            UART_Error  <= 1'b0;
        end else begin
            if (~RX && rx_bit_cnt == 4'b0) begin // Start bit detected
                rx_bit_cnt <= 4'b1;
                clk_div_cnt <= CLK_DIV / 2; // Adjust for middle of start bit sampling
            end else if (rx_bit_cnt > 0) begin
                if (clk_div_cnt < CLK_DIV - 1) begin
                    clk_div_cnt <= clk_div_cnt + 1'b1;
                end else begin
                    clk_div_cnt <= 14'b0;
                    rx_shift_reg <= {RX, rx_shift_reg[9:1]};  // Shift RX data in

                    if (rx_bit_cnt == 4'b10) begin // Stop bit position
                        if (RX == 1'b0) begin
                            UART_Error <= 1'b1; // Framing or stop bit error
                        end else begin
                            UART_Error <= 1'b0;
                            data_out   <= rx_shift_reg[8:1]; // Extract data bits
                        end
                        rx_bit_cnt <= 4'b0; // Reset for next reception
                    end else begin
                        rx_bit_cnt <= rx_bit_cnt + 1'b1;
                    end
                end
            end
        end
    end

endmodule