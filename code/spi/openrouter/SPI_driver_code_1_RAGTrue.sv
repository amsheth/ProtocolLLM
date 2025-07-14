module SPI_driver(
    input logic clk,
    input logic rst,
    input logic [7:0] data_in,
    input logic SPI_MISO,
    input logic SPI_start,
    output logic SPI_MOSI,
    output logic SPI_CLK,
    output logic SPI_EN,
    output logic [7:0] data_out
);

typedef enum { IDLE, SEND, RECEIVE, DONE } state_e;
state_e state;

reg sck; // Clock
reg mosi; // MOSI
reg ss; // Slave select (SPI_EN)
reg [7:0] data_out_reg; // To store received data
reg [3:0] cnt; // Bit counter

// Initialize states and registers
always @(posedge clk or posedge rst) begin
    if (rst) begin
        sck <= 1'b1; // Initial state: high (CPOL=1)
        mosi <= 1'b0;
        ss <= 1'b1; // Initial state: SS high (assuming active low)
        state <= IDLE;
        cnt <= 0;
        data_out_reg <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (SPI_start) begin
                    // Start a new transfer
                    state <= SEND;
                    ss <= 1'b0; // Pull SS low to select slave
                    cnt <= 0;
                end
            end
            SEND: begin
                if (cnt < 8) begin
                    // Send the next bit (MSB first)
                    mosi <= data_in[7 - cnt];
                    // Toggle the clock to low
                    sck <= 1'b0;
                    // Wait for the falling edge to ensure data is stable
                    // Then toggle back to high, creating a rising edge
                    sck <= 1'b1;
                    cnt <= cnt + 1;
                end else begin
                    state <= RECEIVE;
                    cnt <= 0;
                end
            end
            RECEIVE: begin
                if (cnt < 8) begin
                    // Capture the data on the rising edge (CPHA=0)
                    data_out_reg[cnt] <= SPI_MISO;
                    // Toggle the clock to low
                    sck <= 1'b0;
                    // Wait for the falling edge
                    sck <= 1'b1;
                    cnt <= cnt + 1;
                end else begin
                    state <= DONE;
                end
            end
            DONE: begin
                // Deselect the slave
                ss <= 1'b1;
                state <= IDLE;
                // Assign the received data to the output
                data_out <= data_out_reg;
            end
        endcase
    end
end

// Output the signals
assign SPI_MOSI = mosi;
assign SPI_CLK = sck;
assign SPI_EN = ss;

endmodule