module I2C_driver (
    input  logic        clk,        // System clock
    input  logic        rst,        // Asynchronous reset
    input  logic        I2C_Start,  // Initiate a transaction
    input  logic        RW,         // Read/Write control: 0 for write, 1 for read
    input  logic [9:0]  slave_addr, // 10-bit I2C slave address
    input  logic [7:0]  data_in,    // Data to be written
    inout  logic        I2C_SDA,    // I2C data line
    output logic        I2C_SCL,    // I2C clock line
    output logic [7:0]  data_out,   // Data received from slave
    output logic        I2C_En,     // Module enable (active during transaction)
    output logic        busy        // Module busy indicator
);

    // Parameters for I2C timing
    parameter SCL_DIV = 250; // Adjust clock divider factor as needed (assuming a specific frequency)

    typedef enum logic [2:0] {
        IDLE,
        START,
        ADDR,
        DATA,
        STOP
    } state_t;

    state_t state, next_state;

    logic [15:0] clk_div_ctr;
    logic scl_enable;
    logic [8:0] bit_counter;
    logic ack_received;

    // Clock divider for I2C SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_ctr <= 16'd0;
            scl_enable <= 1'b0;
        end else if (clk_div_ctr == (SCL_DIV - 1)) begin
            clk_div_ctr <= 16'd0;
            scl_enable <= ~scl_enable;
        end else begin
            clk_div_ctr <= clk_div_ctr + 1'b1;
        end
    end

    assign I2C_SCL = scl_enable; // I2C clock based on divided clock

    // State transition
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 1'b0;
        end else begin
            state <= next_state;
        end
    end

    // State machine next state logic and output logic
    always_comb begin
        // Default signal values
        busy = 1'b0;
        I2C_En = 1'b0;
        case (state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START;
                    busy = 1'b1;
                end else begin
                    next_state = IDLE;
                end
            end

            START: begin
                // Generate start condition (SDA goes low while SCL is high)
                I2C_En = 1'b1;
                busy = 1'b1;
                // Transaction initiation
                next_state = ADDR;
            end

            ADDR: begin
                // Transmit slave address with R/W bit
                // Logic to manage transfer of address
                I2C_En = 1'b1;
                busy = 1'b1;
                // Check for address transmission and ACK
                if (ack_received) begin
                    next_state = DATA;
                end else begin
                    next_state = ADDR;
                end
            end

            DATA: begin
                // Logic for data transfer
                I2C_En = 1'b1;
                busy = 1'b1;
                // Logic for sending/receiving data
                if (RW == 1'b0) begin
                    // Write operation, handle ACK from slave
                    next_state = STOP;
                end else if (RW == 1'b1) begin
                    // Read operation, wait for data from slave
                    data_out = ack_received ? 8'hXX : data_out; // Your read logic
                    next_state = STOP;
                end
            end

            STOP: begin
                // Generate stop condition
                I2C_En = 1'b1;
                busy = 1'b0;
                next_state = IDLE;
            end

        endcase
    end

    // SDA line control logic
    // Implement tri-state buffer control for SDA
    assign I2C_SDA = (I2C_En && (state == ADDR || state == DATA) && RW == 1'b0) ? 1'bz : 1'b0;

endmodule