module SPI_driver(input logic clk, input logic rst, input logic [7:0] data_in, input logic SPI_MISO, Input logic SPI_start, output logic SPI_MOSI, output logic SPI_CLK, output logic SPI_EN, output logic [7:0] data_out);
    logic [2:0] state;
    localparam IDLE = 3'b000;
    localparam WAIT_ACK = 3'b001;
    localparam TRANSFER = 3'b010;
    localparam DONE = 3'b011;
    
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic [2:0] count;
    logic bit_select;
    
    assign SPI_MOSI = tx_data[count];
    assign SPI_EN = (state == TRANSFER);
    
    always_ff @(posedge clk or negedge rst) begin
        if(!rst) begin
            state <= IDLE;
            count <= 0;
            tx_data <= 'd0;
            rx_data <= 'd0;
            bit_select <= 1'b0;
        end else begin
            case(state)
                IDLE: begin
                    if (SPI_start) begin
                        state <= WAIT_ACK;
                        count <= 7;
                        tx_data <= data_in;
                        bit_select <= 1'b0;
                        rx_data <= 'd0;
                    end else begin
                        state <= IDLE;
                    end
                end
                WAIT_ACK: begin
                    if (SPI_MISO) begin
                        state <= TRANSFER;
                    end else begin
                        state <= WAIT_ACK;
                    end
                end
                TRANSFER: begin
                    if (!SPI_MISO) begin
                        rx_data[count] = SPI_MOSI;
                    end
                    count <= count - 1'b1;
                    
                    if (count == 0) begin
                        state <= DONE;
                    end else begin
                        state <= TRANSFER;
                    end
                end
                DONE: begin
                    data_out <= rx_data;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule