module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
    input  logic       I2C_Start,   // Initiate a transaction when high
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [9:0] slave_addr,  // 10-bit I2C slave address
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

// Internal signals
logic start_flag = 1'b0;
logic stop_flag = 1'b0;
logic [9:0] addr_buf;
logic [7:0] data_buf;
logic [2:0] state = 3'b0;

// State machine implementation
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        start_flag <= 1'b0;
        stop_flag <= 1'b0;
        state <= 3'b0;
        I2C_En <= 1'b0;
    end else begin
        case (state)
            3'b0: begin // Idle state
                if (I2C_Start) begin
                    start_flag <= 1'b1;
                    stop_flag <= 1'b0;
                    state <= 3'b1;
                end else begin
                    start_flag <= 1'b0;
                    stop_flag <= 1'b0;
                    state <= 3'b0;
                end
            end
            3'b1: begin // Start condition state
                if (start_flag) begin
                    I2C_SDA <= 1'b0;
                    I2C_En <= 1'b1;
                    addr_buf <= slave_addr;
                    data_buf <= data_in;
                    state <= 3'b2;
                end else begin
                    start_flag <= 1'b0;
                    stop_flag <= 1'b0;
                    state <= 3'b0;
                end
            end
            3'b2: begin // Addressing state
                if (addr_buf[9] == RW) begin
                    I2C_SDA <= addr_buf[8];
                    addr_buf <= {addr_buf[7:0], 1'b0};
                    data_buf <= data_in;
                    state <= 3'b3;
                end else begin
                    I2C_SDA <= addr_buf[8];
                    addr_buf <= {addr_buf[7:0], 1'b0};
                    data_buf <= data_in;
                    state <= 3'b4;
                end
            end
            3'b3: begin // Data transfer (write) state
                if (data_buf != 8'h00) begin
                    I2C_SDA <= data_buf[7];
                    data_buf <= {data_buf[6:0], 1'b0};
                    state <= 3'b5;
                end else begin
                    stop_flag <= 1'b1;
                    state <= 3'b0;
                end
            end
            3'b4: begin // Data transfer (read) state
                if (data_buf != 8'h00) begin
                    I2C_SDA <= data_buf[7];
                    data_buf <= {data_buf[6:0], 1'b0};
                    state <= 3'b5;
                end else begin
                    stop_flag <= 1'b1;
                    state <= 3'b0;
                end
            end
            3'b5: begin // Stop condition state
                if (stop_flag) begin
                    I2C_SDA <= 1'b1;
                    I2C_En <= 1'b0;
                    state <= 3'b0;
                end else begin
                    stop_flag <= 1'b0;
                    state <= 3'b5;
                end
            end
        endcase
    end
end

// Clock divider implementation
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        I2C_SCL <= 1'b0;
    end else begin
        if (I2C_En) begin
            I2C_SCL <= ~I2C_SCL;
        end else begin
            I2C_SCL <= 1'b0;
        end
    end
end

// Outputs
assign data_out = data_buf;
assign busy = start_flag | stop_flag;

endmodule