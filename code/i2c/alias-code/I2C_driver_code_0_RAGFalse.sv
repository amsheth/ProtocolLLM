module I2C_driver(
    input  logic       clk,         // System clock
    input  logic       rst,         // Asynchronous reset
    input  logic       I2C_Start,   // Initiate a transaction when high
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [6:0] slave_addr,  // 7-bit I2C slave address
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

    // State definitions
    typedef enum logic [2:0] {
        IDLE,
        START,
        ADDRESS,
        ACK_ADDRESS,
        WRITE_DATA,
        ACK_WRITE_DATA,
        READ_DATA,
        ACK_READ_DATA,
        STOP
    } state_t;

    state_t state, next_state;

    // Clock divider for I2C SCL
    logic [7:0] clk_div;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 8'd0;
            I2C_SCL <= 1'b0;
        end else begin
            if (clk_div == 8'd0) begin
                clk_div <= 8'd255; // Adjust for desired SCL frequency
                I2C_SCL <= ~I2C_SCL;
            end else begin
                clk_div <= clk_div - 1;
            end
        end
    end

    // I2C SDA tristate control
    assign I2C_SDA = (state == IDLE || state == START || state == STOP)? 1'bz : I2C_SDA;

    // State machine logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 1'b0;
            I2C_En <= 1'b0;
        end else begin
            state <= next_state;
            busy <= (state!= IDLE);
            I2C_En <= (state!= IDLE);
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START;
                end
            end
            START: begin
                I2C_SDA <= 1'b0;
                next_state = ADDRESS;
            end
            ADDRESS: begin
                I2C_SDA <= {slave_addr, RW};
                next_state = ACK_ADDRESS;
            end
            ACK_ADDRESS: begin
                // Wait for ACK from slave
                next_state = (I2C_SDA == 1'b0)? (RW? READ_DATA : WRITE_DATA) : STOP;
            end
            WRITE_DATA: begin
                I2C_SDA <= data_in[7];
                next_state = ACK_WRITE_DATA;
            end
            ACK_WRITE_DATA: begin
                // Wait for ACK from slave
                next_state = (I2C_SDA == 1'b0)? (RW? READ_DATA : STOP) : WRITE_DATA;
            end
            READ_DATA: begin
                // Read data from slave
                data_out[7] <= I2C_SDA;
                next_state = ACK_READ_DATA;
            end
            ACK_READ_DATA: begin
                // Send ACK/NACK to slave
                next_state = STOP;
            end
            STOP: begin
                I2C_SDA <= 1'b1;
                next_state = IDLE;
            end
        endcase
    end

endmodule