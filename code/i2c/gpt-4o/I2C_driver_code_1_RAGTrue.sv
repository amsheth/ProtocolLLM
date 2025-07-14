module I2C_driver(
    input  logic       clk,         // System clock
    input  logic       rst,         // Asynchronous reset
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

    // State declarations
    typedef enum logic [3:0] {
        IDLE,
        START,
        ADDR,
        DATA,
        ACK,
        STOP
    } state_t;

    state_t state, next_state;

    // Clock Division for I2C SCL generation
    parameter integer CLOCK_DIVIDER = 250; // Example divider value
    logic [7:0] clk_div_count;
    logic scl_clk;

    // SDA line control
    logic sda_out;
    assign I2C_SDA = (state == START || state == ADDR || state == DATA) ? sda_out : 1'bz;

    // Control signals
    logic [3:0] bit_count;
    logic [7:0] data_buf;
    logic ack_bit;

    // Clock Divider for SCL
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_count <= 0;
            scl_clk <= 1'b1;
        end else begin
            if (clk_div_count == CLOCK_DIVIDER) begin
                clk_div_count <= 0;
                scl_clk <= ~scl_clk; // Toggle SCL
            end else begin
                clk_div_count <= clk_div_count + 1;
            end
        end
    end

    assign I2C_SCL = scl_clk;

    // State Machine logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 0;
            I2C_En <= 0;
        end else begin
            state <= next_state;
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        I2C_En = 0;
        busy = 0;
        ack_bit = 0;
        case (state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START;
                    busy = 1;
                end
            end
            START: begin
                I2C_En = 1;
                sda_out = 0; // Generate start condition
                next_state = ADDR;
                bit_count = 0;
                data_buf = {slave_addr[9:0], RW}; // 10-bit address + R/W
            end
            ADDR: begin
                I2C_En = 1;
                sda_out = data_buf[9];
                if (bit_count < 10) begin
                    data_buf <= {data_buf[8:0], 1'b0};
                    bit_count <= bit_count + 1;
                end else begin
                    next_state = ACK;
                end
            end
            DATA: begin
                I2C_En = 1;
                if (RW) begin // Read operation
                    data_out[7:0] <= {data_out[6:0], I2C_SDA};
                    if (bit_count == 8) begin
                        ack_bit <= 1; // Send NACK
                        next_state = ACK;
                    end else begin
                        bit_count <= bit_count + 1;
                    end
                end else begin // Write operation
                    sda_out = data_in[7];
                    if (bit_count < 8) begin
                        data_in <= {data_in[6:0], 1'b0};
                        bit_count <= bit_count + 1;
                    end else begin
                        next_state = ACK;
                    end
                end
            end
            ACK: begin
                I2C_En = 1;
                if (!RW || bit_count == 8) begin
                    sda_out = ack_bit; // NACK for reads after one byte
                    next_state = STOP;
                end else begin
                    next_state = DATA;
                    bit_count <= 0;
                end
            end
            STOP: begin
                I2C_En = 1;
                sda_out = 1;
                next_state = IDLE;
            end
        endcase
    end

endmodule