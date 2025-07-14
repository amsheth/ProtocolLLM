module I2C_driver(
    input  logic       clk,
    input  logic       rst,
    input  logic       I2C_Start,
    input  logic       RW,
    input  logic [9:0] slave_addr,
    input  logic [7:0] data_in,
    inout  logic       I2C_SDA,
    output logic       I2C_SCL,
    output logic [7:0] data_out,
    output logic       I2C_En,
    output logic       busy
);

// Parameters for clock divider and SCL frequency
parameter CLK_DIV = 100; // Example divisor, adjust based on desired SCL frequency

// Internal signals
logic [9:0] addr_reg;
logic [7:0] data_in_reg;
logic [7:0] data_out_reg;
logic       sda_oen;
logic       scl_en;
logic       start_condition;
logic       stop_condition;
logic       read_data;
logic       write_data;
logic       ack_received;
logic       busy_int;

// State machine states
typedef enum logic [3:0] {
    IDLE,
    START,
    ADDR_HIGH,
    ADDR_LOW,
    RW_BIT,
    DATA_WRITE,
    DATA_READ,
    ACK,
    STOP
} state_t;

state_t current_state, next_state;

// Clock divider for SCL generation
logic [15:0] clk_div_counter;
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        clk_div_counter <= 0;
    else if (clk_div_counter == CLK_DIV - 1)
        clk_div_counter <= 0;
    else
        clk_div_counter <= clk_div_counter + 1;
end

assign I2C_SCL = clk_div_counter[15] & scl_en;

// State machine logic
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

always_comb begin
    next_state = current_state;
    start_condition = 0;
    stop_condition = 0;
    read_data = 0;
    write_data = 0;
    ack_received = 0;
    scl_en = 1;
    sda_oen = 1;

    case (current_state)
        IDLE: begin
            if (I2C_Start) begin
                next_state = START;
                start_condition = 1;
                busy_int = 1;
            end
        end

        START: begin
            next_state = ADDR_HIGH;
            addr_reg = slave_addr;
        end

        ADDR_HIGH: begin
            next_state = ADDR_LOW;
        end

        ADDR_LOW: begin
            next_state = RW_BIT;
        end

        RW_BIT: begin
            if (RW == 0)
                next_state = DATA_WRITE;
            else
                next_state = DATA_READ;
        end

        DATA_WRITE: begin
            if (ack_received) begin
                if (data_in_reg != 8'b0)
                    next_state = DATA_WRITE;
                else
                    next_state = STOP;
            end
        end

        DATA_READ: begin
            if (ack_received) begin
                if (data_out_reg != 8'b0)
                    next_state = DATA_READ;
                else
                    next_state = ACK;
            end
        end

        ACK: begin
            next_state = STOP;
        end

        STOP: begin
            next_state = IDLE;
            stop_condition = 1;
            busy_int = 0;
        end

        default: next_state = IDLE;
    endcase
end

// SDA control logic
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        I2C_SDA <= 1'b1;
    else if (sda_oen)
        I2C_SDA <= 1'b1;
    else
        I2C_SDA <= data_in_reg[7];
end

// Data transfer logic
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        data_in_reg <= 8'b0;
        data_out_reg <= 8'b0;
    end else begin
        if (write_data)
            data_in_reg <= {data_in_reg[6:0], I2C_SDA};
        if (read_data)
            data_out_reg <= {data_out_reg[6:0], I2C_SDA};
    end
end

// Assign outputs
assign busy = busy_int;
assign data_out = data_out_reg;

endmodule