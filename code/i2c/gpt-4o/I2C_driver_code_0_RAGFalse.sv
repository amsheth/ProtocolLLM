module I2C_driver(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous reset
    input  logic       I2C_Start,  // Start signal
    input  logic       RW,         // Read/Write Control
    input  logic [6:0] slave_addr, // Slave address
    input  logic [7:0] data_in,    // Input data for writing
    inout  logic       I2C_SDA,    // Bidirectional data line
    output logic       I2C_SCL,    // Clock line for I2C
    output logic [7:0] data_out,   // Output data from reading
    output logic       I2C_En,     // Enable signal
    output logic       busy        // Busy signal
);

    typedef enum logic [2:0] {
        IDLE,
        START,
        ADDR,
        DATA,
        RECEIVE,
        STOP
    } state_t;

    state_t state, next_state;
    logic [15:0] clk_div_counter;
    logic scl_enable;
    logic sda_dir;   // 0: input, 1: output
    logic [3:0] bit_count;
    logic ack_check;

    // Parameters
    parameter CLK_DIV = 1000; // Adjust this to set the SCL frequency

    // Clock Divider for I2C SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_counter <= 0;
            I2C_SCL <= 1;
        end else begin
            if (clk_div_counter == CLK_DIV) begin
                clk_div_counter <= 0;
                I2C_SCL <= ~I2C_SCL;
            end else begin
                clk_div_counter <= clk_div_counter + 1;
            end
        end
    end

    // State machine for I2C control
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 0;
            I2C_SDA <= 1'bz;
            sda_dir <= 1;
            bit_count <= 0;
        end else begin
            state <= next_state;
            if (state != IDLE) busy <= 1;
            else busy <= 0;
        end
    end

    // Next state logic
    always_comb begin
        next_state = state; // Default to stay in the same state
        case (state)
            IDLE: begin
                I2C_En = 0;
                if (I2C_Start) begin
                    next_state = START;
                    sda_dir = 1; // Set SDA to output
                end
            end

            START: begin
                I2C_En = 1;
                if (clk_div_counter == 0) begin
                    I2C_SDA = 0; // Start condition
                    next_state = ADDR;
                end
            end

            ADDR: begin
                I2C_En = 1;
                if (clk_div_counter == 0) begin
                    if (bit_count < 7) begin
                        I2C_SDA = slave_addr[6 - bit_count];
                        bit_count = bit_count + 1;
                    end else begin
                        I2C_SDA = RW;
                        bit_count = 0;
                        next_state = DATA;
                    end
                end
            end

            DATA: begin
                I2C_En = 1;
                if (clk_div_counter == 0) begin
                    if (RW == 0) begin
                        if (bit_count < 8) begin
                            I2C_SDA = data_in[7-bit_count];
                            bit_count = bit_count + 1;
                        end else begin
                            sda_dir = 0; // Switch to input for ACK
                            ack_check = I2C_SDA;
                            bit_count = 0;
                            next_state = STOP;
                        end
                    end else begin
                        sda_dir = 0; // Switch to input for reading
                        next_state = RECEIVE;
                    end
                end
            end

            RECEIVE: begin
                I2C_En = 1;
                if (clk_div_counter == 0) begin
                    if (bit_count < 8) begin
                        data_out[7-bit_count] = I2C_SDA;
                        bit_count = bit_count + 1;
                    end else begin
                        sda_dir = 1; // Switch to output for NACK
                        I2C_SDA = 1; // NACK
                        next_state = STOP;
                    end
                end
            end

            STOP: begin
                I2C_En = 1;
                if (clk_div_counter == 0) begin
                    I2C_SDA = 0;
                end else if (clk_div_counter == CLK_DIV/2) begin
                    I2C_SDA = 1;
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Bidirectional I2C SDA handling
    assign I2C_SDA = (sda_dir ? 1'bz : I2C_SDA);

endmodule