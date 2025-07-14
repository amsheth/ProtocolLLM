module I2C_driver (
    input  logic clk,
    input  logic rst,
    input  logic I2C_Start,
    input  logic RW,
    input  logic [9:0] slave_addr,
    input  logic [7:0] data_in,
    inout  logic I2C_SDA,
    output logic I2C_SCL,
    output logic [7:0] data_out,
    output logic I2C_En,
    output logic busy
);

parameter CLK_DIV = 10; // Clock divider factor for SCL frequency

logic clk_scl;
logic sda_out;
assign I2C_SDA = (I2C_SCL && !clk_scl) ? sda_out : 'z;

typedef enum {
    IDLE,
    START_CONDITION,
    ADDRESS_WRITE,
    RW_BIT,
    DATA_WRITE,
    DATA_READ,
    ACK_NACK,
    STOP_CONDITION
} state_t;

state_t current_state, next_state;
logic [3:0] bit_count;
logic [7:0] shift_reg;
logic ack_received;
logic write_transaction;

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        current_state <= IDLE;
        I2C_SCL <= 1'b1;
        busy <= 1'b0;
        I2C_En <= 1'b0;
    end else begin
        current_state <= next_state;
        case (current_state)
            START_CONDITION: begin
                I2C_SDA <= 1'b0;
                I2C_SCL <= 1'b1;
                busy <= 1'b1;
                I2C_En <= 1'b1;
            end
            ADDRESS_WRITE, RW_BIT, DATA_WRITE, DATA_READ, ACK_NACK: begin
                I2C_SDA <= shift_reg[7];
                shift_reg <= {shift_reg[6:0], 1'b0};
                bit_count <= bit_count + 1;
            end
            STOP_CONDITION: begin
                I2C_SDA <= 1'b0;
                busy <= 1'b0;
                I2C_En <= 1'b0;
            end
        endcase
    end
end

always_ff @(posedge clk_scl or posedge rst) begin
    if (rst) begin
        sda_out <= 1'b1;
        ack_received <= 1'b0;
        shift_reg <= (RW == 0) ? {slave_addr[7:0], RW} : slave_addr[9];
        bit_count <= 4'd0;
        write_transaction <= (RW == 0);
    end else begin
        case (current_state)
            START_CONDITION: begin
                sda_out <= 1'b0;
            end
            ADDRESS_WRITE, RW_BIT, DATA_WRITE, ACK_NACK: begin
                if (bit_count == 4'd7) begin
                    sda_out <= shift_reg[7];
                    bit_count <= 4'd0;
                end else begin
                    bit_count <= bit_count + 1;
                end
            end
            DATA_READ: begin
                data_out <= {data_out[6:0], I2C_SDA};
            end
            STOP_CONDITION: begin
                sda_out <= 1'b1;
            end
        endcase

        if (current_state == ACK_NACK) begin
            ack_received <= !I2C_SDA;
        end
    end
end

always_comb begin
    next_state = current_state;

    case (current_state)
        IDLE: begin
            if (I2C_Start) begin
                next_state = START_CONDITION;
            end
        end
        START_CONDITION: begin
            next_state = ADDRESS_WRITE;
        end
        ADDRESS_WRITE: begin
            if (bit_count == 4'd10) begin
                next_state = RW_BIT;
            end
        end
        RW_BIT: begin
            if (bit_count == 4'd8) begin
                if (write_transaction) begin
                    next_state = DATA_WRITE;
                end else begin
                    next_state = DATA_READ;
                end
            end
        end
        DATA_WRITE: begin
            if (bit_count == 4'd8) begin
                next_state = ACK_NACK;
            end
        end
        DATA_READ: begin
            if (bit_count == 4'd8) begin
                next_state = ACK_NACK;
            end
        end
        ACK_NACK: begin
            if (bit_count == 4'd1) begin
                if (write_transaction) begin
                    next_state = STOP_CONDITION;
                end else begin
                    next_state = DATA_READ;
                end
            end
        end
        STOP_CONDITION: begin
            next_state = IDLE;
        end
    endcase

    // Clock divider
    if (current_state != IDLE && current_state != START_CONDITION) begin
        clk_scl <= ~clk_scl;
    end else begin
        clk_scl <= 1'b0;
    end
end

// Clock divider logic
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        clk_scl <= 1'b0;
    end else if (current_state == START_CONDITION || current_state == STOP_CONDITION) begin
        clk_scl <= 1'b0;
    end else begin
        static integer count = 0;
        if (count == CLK_DIV - 1) begin
            count <= 0;
            clk_scl <= ~clk_scl;
        end else begin
            count <= count + 1;
        end
    end
end

endmodule