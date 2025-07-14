module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
    input  logic       I2C_Start,   // Initiate a transaction when high
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [6:0] slave_addr,  // 7-bit I2C slave address input
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line output
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

    typedef enum {IDLE, START, ADDR, DATA, ACK, STOP} state_t;
    state_t state, next_state;

    logic [7:0] data_buffer;  // Buffer to hold data for transmission/reception
    logic       sda_out;      // Output control signal for I2C SDA
    logic       scl_clk;      // Generated clock signal for I2C SCL
    logic [3:0] bit_cnt;      // Counter for the bits being transmitted/received
    logic [2:0] clk_div;      // Clock divider counter

    // Clock Divider to generate SCL from system clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 3'b0;
            scl_clk <= 1'b0;
        end else begin
            clk_div <= clk_div + 1;
            scl_clk <= (clk_div == 3'd4); // Adjust this value based on the required SCL frequency
        end
    end

    // I2C SDA handling (bidirectional)
    always_comb begin
        if (sda_out) begin
            I2C_SDA = 1'bz;
        end else begin
            I2C_SDA = data_buffer[7-bit_cnt];
        end
    end

    // State Machine for I2C transaction
    always_ff @(posedge scl_clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            bit_cnt <= 4'b0;
            data_buffer <= 8'b0;
            busy <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (I2C_Start) begin
                        state <= START;
                        busy <= 1'b1;
                    end
                end
                START: begin
                    // Generate start condition on I2C bus
                    sda_out = 1'b0;
                    bit_cnt = 4'd7;
                    state <= ADDR;
                end
                ADDR: begin
                    if (bit_cnt == 0) begin
                        state <= DATA;
                    end else begin
                        // Shift data to I2C slave
                        sda_out = slave_addr[6-bit_cnt];
                        bit_cnt = bit_cnt - 1;
                    end
                end
                DATA: begin
                    if (RW == 0) begin
                        // Write operation
                        sda_out = data_in[7-bit_cnt];
                        if (bit_cnt == 0) state <= ACK;
                    end else begin
                        // Read operation
                        sda_out = 1'b0; // Send NACK after last bit for read
                        if (bit_cnt == 0) state <= STOP;
                    end
                end
                ACK: begin
                    if (RW == 0) begin
                        // Write operation, wait for ACK/NACK from slave
                        sda_out = 1'b0; // Send ACK
                        bit_cnt = 4'd7;
                        state <= DATA;
                    end else begin
                        // Read operation, get data and send ACK/NACK
                        data_buffer[7-bit_cnt] = I2C_SDA;
                        if (bit_cnt == 0) state <= STOP;
                    end
                end
                STOP: begin
                    // Generate stop condition on I2C bus
                    sda_out = 1'b0;
                    busy <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule