module UART_driver(
    input  logic clk, rst,
    input  logic UART_Start,
    input  logic [8:0] data_in,
    output logic RX, TX,
    output logic [8:0] data_out,
    output logic UART_Ready, UART_Busy, UART_Error
);

// Internal signals
logic [7:0] transmit_data;
logic [15:0] baud_rate;
logic start_bit, stop_bit, parity_bit;

// Clock and reset synchronization
always_ff @(posedge clk or negedge rst) begin
    if (!rst) begin
        transmit_data <= 0;
        baud_rate <= 0;
        start_bit <= 0;
        stop_bit <= 0;
        parity_bit <= 0;
    end else begin
        // Update internal signals based on input signals
        if (UART_Start) begin
            transmit_data <= data_in[7:0];
            baud_rate <= data_in[8:15];
            start_bit <= data_in[9];
            stop_bit <= data_in[10];
            parity_bit <= data_in[11];
        end
    end
end

// UART transmitter
always_comb begin
    if (transmit_data == 0) begin
        TX <= 0;
    end else begin
        TX <= transmit_data[7:0];
        transmit_data <= transmit_data << 1;
    end
end

// UART receiver
always_comb begin
    if (RX == 0) begin
        data_out <= 0;
    end else begin
        data_out <= RX[7:0];
        data_out <= data_out << 1;
    end
end

// UART busy and error signals
always_comb begin
    if (transmit_data == 0) begin
        UART_Busy <= 0;
        UART_Error <= 0;
    end else begin
        UART_Busy <= 1;
        UART_Error <= 0;
    end
end

// UART ready signal
always_comb begin
    if (transmit_data == 0) begin
        UART_Ready <= 0;
    end else begin
        UART_Ready <= 1;
    end
end

endmodule