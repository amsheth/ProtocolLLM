module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
    input  logic       I2C_Start,   // Initiate a transaction when high input
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read input
    input  logic [9:0] slave_addr,  // 10-bit I2C slave address input
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line output
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

// Parameters for clock divider and timing
parameter CLK_FREQ = 50_000_000;   // System clock frequency in Hz
parameter I2C_FREQ = 100_000;      // Desired I2C frequency in Hz
parameter CLK_DIV = CLK_FREQ / (I2C_FREQ * 4); // Clock divider factor

// Internal signals
logic [7:0] clk_div_cnt;
logic       scl_tick;

// State machine states
typedef enum logic [3:0] {
    IDLE,
    START,
    ADDR1,
    ADDR2,
    RW_BIT,
    ACK_ADDR,
    WRITE_DATA,
    READ_DATA,
    STOP
} state_t;

state_t state, next_state;

// Clock divider to generate I2C SCL frequency
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        clk_div_cnt <= '0;
    else if (clk_div_cnt == CLK_DIV - 1)
        clk_div_cnt <= '0;
    else
        clk_div_cnt <= clk_div_cnt + 1'b1;
end

assign scl_tick = (clk_div_cnt == CLK_DIV / 2);

// State machine for I2C protocol handling
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        state <= IDLE;
    else
        state <= next_state;
end

always_comb begin
    next_state = state;

    case (state)
        IDLE: begin
            if (I2C_Start)
                next_state = START;
        end
        START: begin
            // Generate start condition and move to address transmission
            next_state = ADDR1;
        end
        ADDR1, ADDR2, RW_BIT: begin
            // Transmit 10-bit slave address and R/W bit
            if (scl_tick)
                next_state = state + 1'b1;
        end
        ACK_ADDR: begin
            // Check for ACK from slave
            if (scl_tick) begin
                if (I2C_SDA == 1'b0) begin
                    if (RW == 0)
                        next_state = WRITE_DATA;
                    else
                        next_state = READ_DATA;
                end else begin
                    // Handle NACK condition
                    next_state = STOP;
                end
            end
        end
        WRITE_DATA: begin
            // Transmit data byte and check for ACK
            if (scl_tick) begin
                if (I2C_SDA == 1'b0)
                    next_state = STOP;
                else
                    // Handle NACK condition
                    next_state = STOP;
            end
        end
        READ_DATA: begin
            // Receive data byte and send ACK/NACK
            if (scl_tick) begin
                if (I2C_SCL == 1'b0)
                    data_out <= {data_out[6:0], I2C_SDA};
                else
                    next_state = STOP;
            end
        end
        STOP: begin
            // Generate stop condition and return to IDLE
            next_state = IDLE;
        end
    endcase
end

// Control signals and SCL/SDA handling
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        I2C_SCL <= 1'b1;
        I2C_SDA <= 1'bz; // Tri-state for bidirectional data line
        busy <= 1'b0;
        I2C_En <= 1'b0;
        data_out <= '0;
    end else begin
        case (state)
            IDLE: begin
                busy <= 1'b0;
                I2C_En <= 1'b0;
            end
            START: begin
                I2C_SCL <= 1'b1;
                I2C_SDA <= 1'b0; // Start condition
                busy <= 1'b1;
                I2C_En <= 1'b1;
            end
            ADDR1, ADDR2, RW_BIT: begin
                if (scl_tick) begin
                    I2C_SCL <= ~I2C_SCL;
                    case (state)
                        ADDR1: I2C_SDA <= slave_addr[9];
                        ADDR2: I2C_SDA <= slave_addr[state - ADDR1];
                        RW_BIT: I2C_SDA <= RW;
                    endcase
                end
            end
            ACK_ADDR, WRITE_DATA: begin
                if (scl_tick) begin
                    I2C_SCL <= ~I2C_SCL;
                    case (state)
                        ACK_ADDR: I2C_SDA <= 1'bz; // Tri-state for reading ACK/NACK
                        WRITE_DATA: I2C_SDA <= data_in[7 - (clk_div_cnt / 2)];
                    endcase
                end
            end
            READ_DATA: begin
                if (scl_tick) begin
                    I2C_SCL <= ~I2C_SCL;
                    if (I2C_SCL == 1'b0)
                        I2C_SDA <= 1'bz; // Tri-state for reading data
                    else
                        I2C_SDA <= 1'b0; // Send ACK/NACK based on implementation needs
                end
            end
            STOP: begin
                I2C_SCL <= 1'b0;
                I2C_SDA <= 1'b0;
                #1ps I2C_SDA <= 1'b1; // Stop condition
                busy <= 1'b0;
                I2C_En <= 1'b0;
            end
        endcase
    end
end

endmodule