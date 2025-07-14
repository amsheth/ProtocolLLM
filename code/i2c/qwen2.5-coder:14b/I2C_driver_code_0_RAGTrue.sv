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

// Parameters for clock divider and SCL frequency
parameter CLK_DIV = 10; // Example divisor, adjust based on desired SCL frequency

// Internal signals
logic [3:0] clk_cnt;
logic [3:0] bit_cnt;
logic [7:0] shift_reg;
logic       sda_out;
logic       sda_in;
logic       scl_en;
logic       start_gen;
logic       stop_gen;
logic       data_valid;

// State machine states
typedef enum logic [2:0] {
    IDLE,
    START,
    ADDR,
    DATA,
    ACK,
    STOP
} state_t;

state_t state, next_state;

// Clock divider for SCL generation
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        clk_cnt <= 4'b0;
    else if (scl_en && clk_cnt < CLK_DIV - 1)
        clk_cnt <= clk_cnt + 1;
    else
        clk_cnt <= 4'b0;
end

assign I2C_SCL = (clk_cnt == CLK_DIV / 2);

// State machine logic
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        state <= IDLE;
    else
        state <= next_state;
end

always_comb begin
    next_state = state;
    I2C_SDA = 'z; // Default to high-impedance
    scl_en = 0;
    start_gen = 0;
    stop_gen = 0;
    data_valid = 0;

    case (state)
        IDLE: begin
            if (I2C_Start) begin
                next_state = START;
                I2C_En = 1;
                busy = 1;
            end else begin
                I2C_En = 0;
                busy = 0;
            end
        end

        START: begin
            start_gen = 1;
            if (clk_cnt == CLK_DIV - 1) begin
                next_state = ADDR;
                bit_cnt = 7; // Start with MSB of address
                shift_reg = {slave_addr, RW};
            end
        end

        ADDR: begin
            scl_en = 1;
            I2C_SDA = shift_reg[bit_cnt];
            if (clk_cnt == CLK_DIV - 1) begin
                bit_cnt--;
                if (bit_cnt < 0)
                    next_state = ACK;
            end
        end

        DATA: begin
            scl_en = 1;
            I2C_SDA = shift_reg[bit_cnt];
            if (clk_cnt == CLK_DIV - 1) begin
                bit_cnt--;
                if (bit_cnt < 0) begin
                    if (RW)
                        next_state = ACK;
                    else
                        next_state = STOP;
                end
            end
        end

        ACK: begin
            scl_en = 1;
            I2C_SDA = 'z; // Release SDA for ACK/NACK
            if (clk_cnt == CLK_DIV - 1) begin
                sda_in = I2C_SDA; // Capture ACK/NACK
                data_valid = 1;
                if (!sda_in && RW)
                    next_state = DATA;
                else
                    next_state = STOP;
            end
        end

        STOP: begin
            stop_gen = 1;
            if (clk_cnt == CLK_DIV - 1) begin
                next_state = IDLE;
                I2C_En = 0;
                busy = 0;
            end
        end
    endcase
end

// Start and Stop condition generation
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        sda_out <= 1'b1;
    else if (start_gen || stop_gen) begin
        if (start_gen)
            sda_out <= 0;
        else
            sda_out <= 1;
    end
end

assign I2C_SDA = start_gen ? 0 : stop_gen ? 1 : sda_out;

// Data output for read operations
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        data_out <= 8'b0;
    else if (data_valid && RW) begin
        data_out[7 - bit_cnt] = I2C_SDA;
    end
end

endmodule