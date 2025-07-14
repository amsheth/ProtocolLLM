module I2C_driver(
    input  logic       clk,
    input  logic       rst,
    input  logic       I2C_Start,
    input  logic       RW,
    input  logic [6:0] slave_addr,
    input  logic [7:0] data_in,
    inout  logic       I2C_SDA,
    output logic       I2C_SCL,
    output logic [7:0] data_out,
    output logic       I2C_En,
    output logic       busy
);

// Define state machine states
typedef enum logic [3:0] {
    IDLE,
    START,
    SLAVE_ADDR,
    RW_BIT,
    DATA,
    ACK,
    STOP,
    READ_DATA,
    READ_ACK,
    FINISH
} i2c_state_t;

i2c_state_t current_state, next_state;
logic sda_in; // Internal signal for SDA input
logic [7:0] shift_reg;
logic [3:0] bit_count;
logic scl_en, scl_out, sda_out, sda_en;
assign I2C_SCL = scl_out ? 1'bZ : scl_en;
assign I2C_SDA = sda_out ? 1'bZ : sda_en;

// Clock divider
parameter SCL_FREQ = 50_000; // Desired I2C frequency in Hz
localparam CLK_DIV = clk_freq / (SCL_FREQ * 4); // I2C timing requires at least 4 clock cycles per bit
logic [16:0] clock_divider;
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        clock_divider <= 0;
    else if (clock_divider == CLK_DIV - 1)
        clock_divider <= 0;
    else
        clock_divider <= clock_divider + 1;
end

// SCL signal generation
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        scl_en <= 1'b1;
    else if (clock_divider == CLK_DIV - 1) // Toggle SCL at half the desired period
        scl_en <= ~scl_en;
end

assign scl_out = scl_en;

// State machine logic
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

always_comb begin
    unique case (current_state)
        IDLE: begin
            I2C_En = 1'b0;
            busy = 1'b0;
            // Other control signals default values...
            if (I2C_Start)
                next_state = START;
            else
                next_state = IDLE;
        end

        START: begin
            I2C_En = 1'b1;
            busy = 1'b1;
            scl_out = 1'b1;
            sda_en = 0;
            // Other control signals default values...
            next_state = SLAVE_ADDR;
        end

        // Additional states (SLAVE_ADDR, RW_BIT, DATA, ACK, STOP, READ_DATA, READ_ACK) would go here
        // Each state would handle its own part of the I2C transaction,
        // update shift_reg and bit_count as needed for data transfers,
        // and transition to the next appropriate state.

        FINISH: begin
            scl_out = 1'b1;
            sda_en = 0;
            busy = 1'b0;
            if (!I2C_Start) // Wait until a new transaction is initiated
                I2C_En <= 1'b0;
            next_state = IDLE;
        end

        default: begin
            next_state = IDLE;
        end
    endcase
end

// SDA input handling
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        sda_in <= 1'bZ;
    else if (scl_en == 0 && scl_out == 1)
        sda_in <= I2C_SDA; // Capture SDA on the falling edge of SCL
end

// Data input/output handling
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        data_out <= 8'b0;
    else if (current_state == READ_DATA && scl_en == 0 && scl_out == 1) begin
        // Shift in new bit from slave
        data_out[7:1] = data_out[6:0];
        data_out[0] = sda_in;
    end
end

// Additional logic for handling the specific details of each state would be here

endmodule