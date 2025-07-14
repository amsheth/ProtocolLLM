module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
    input  logic       I2C_Start,   // Initiate a transaction when high
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [9:0] slave_addr,  // 10-bit I2C slave address input
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line output
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

    // Clock divider to generate SCL
    logic [15:0] clk_div;
    parameter integer CLK_DIV_MAX = 16'd24; // Example value, adjust for your specific frequency
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div <= 16'd0;
        end else begin
            clk_div <= clk_div + 1;
        end
    end
    assign I2C_SCL = clk_div[CLK_DIV_MAX];

    // Define states for the FSM
    typedef enum logic [3:0] {IDLE, START, ADDR, ACK_WAIT, DATA, RESP, STOP} state_t;
    state_t state, next_state;

    // Internal signals
    logic start_condition;
    logic stop_condition;
    logic shift_data;
    logic send_ack;
    logic receive_ack;
    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic ack_received;

    // I2C signals handling
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: if (I2C_Start) next_state = START;
            START: next_state = ADDR;
            ADDR: if (bit_cnt == 3'd7 && RW == 1'b0) next_state = ACK_WAIT; // Write address case
                  else if (bit_cnt == 3'd6) next_state = ACK_WAIT; // Read address case
            ACK_WAIT: if (receive_ack) next_state = DATA;
            DATA: if (bit_cnt == 3'd7 && RW == 1'b0) next_state = STOP;
                  else if (bit_cnt == 3'd7 && RW == 1'b1) next_state = RESP;
            RESP: next_state = ACK_WAIT; // Wait for acknowledge after reading data
            STOP: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt <= 3'd0;
        end else begin
            case (state)
                ADDR: if (!I2C_SCL && bit_cnt < 3'd7) bit_cnt <= bit_cnt + 1;
                      else if (!I2C_SCL && bit_cnt == 3'd7) bit_cnt <= 3'd0; // Reset for next transaction or read operation
                DATA: if (!I2C_SCL && shift_data) bit_cnt <= bit_cnt + 1;
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'd0;
        end else begin
            case (state)
                ADDR: if (!I2C_SCL && bit_cnt < 3'd7) shift_reg <= {shift_reg[6:0], I2C_SDA};
                      else if (!I2C_SCL && bit_cnt == 3'd7) begin
                          if (RW == 1'b0) shift_reg <= data_in; // Load input data for write
                          else shift_reg <= {shift_reg[6:0], I2C_SDA}; // For read, keep shifting until last bit
                      end
                DATA: if (!I2C_SCL && shift_data) shift_reg <= {shift_reg[6:0], I2C_SDA};
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'd0;
        end else begin
            case (state)
                RESP: if (!I2C_SCL && bit_cnt == 3'd7) data_out <= shift_reg; // Output read data at the end of the transaction
            endcase
        end
    end

    // Generate start and stop conditions
    assign start_condition = (state == START && !I2C_SCL);
    assign stop_condition  = (state == STOP && I2C_SCL);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0;
        end else begin
            case (state)
                START: busy <= 1'b1;
                STOP: busy <= 1'b0;
                default: ;
            endcase
        end
    end

endmodule