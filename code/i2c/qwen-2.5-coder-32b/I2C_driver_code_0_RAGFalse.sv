module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
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

    // Parameters
    parameter CLK_FREQ = 50_000_000; // System clock frequency in Hz
    parameter I2C_FREQ = 100_000;   // Desired I2C frequency in Hz
    parameter CLK_DIV  = CLK_FREQ / (5 * I2C_FREQ); // Clock divider factor for 50% duty cycle

    // Internal signals
    logic [15:0] clk_div_cnt; // Clock divider counter
    logic        scl;           // Internal SCL signal
    logic        scl_en;        // SCL enable signal
    logic        sda;           // Internal SDA signal
    logic        sda_en;        // SDA enable signal
    logic [3:0]  state;         // State machine state
    logic [3:0]  next_state;    // Next state machine state
    logic [2:0]  bit_cnt;       // Bit counter for data/address transfer
    logic [7:0]  shift_reg;     // Shift register for data/address transfer
    logic        start_cond;    // Start condition flag
    logic        stop_cond;     // Stop condition flag
    logic        ack;           // Acknowledge signal from slave

    // Clock divider
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_cnt <= '0;
            scl <= 1'b1;
        end else if (scl_en) begin
            if (clk_div_cnt == CLK_DIV - 1) begin
                clk_div_cnt <= '0;
                scl <= ~scl;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1;
            end
        end
    end

    // SCL enable
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            scl_en <= 1'b0;
        else if (state == IDLE && I2C_Start)
            scl_en <= 1'b1;
        else if (state == STOP)
            scl_en <= 1'b0;
    end

    // State machine
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
                if (I2C_Start) begin
                    next_state = START;
                end
            end
            START: begin
                next_state = ADDR;
            end
            ADDR: begin
                if (bit_cnt == 0) begin
                    next_state = RW ? RDATA : WDATA;
                end
            end
            WDATA: begin
                if (bit_cnt == 0) begin
                    next_state = ACK;
                end
            end
            ACK: begin
                next_state = RW ? RDATA : STOP;
            end
            RDATA: begin
                if (bit_cnt == 0) begin
                    next_state = RW ? ACK : STOP;
                end
            end
            STOP: begin
                next_state = IDLE;
            end
        endcase
    end

    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bit_cnt <= 3'b111;
        else if (state == START || state == ACK || state == STOP)
            bit_cnt <= 3'b111;
        else if (scl && ~scl_en)
            bit_cnt <= bit_cnt - 1;
    end

    // Shift register
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            shift_reg <= {slave_addr, RW};
        else if (state == ADDR && scl && ~scl_en)
            shift_reg <= {shift_reg[6:0], 1'b0};
        else if (state == WDATA && scl && ~scl_en)
            shift_reg <= {shift_reg[6:0], 1'b0};
        else if (state == RDATA && scl && ~scl_en)
            shift_reg <= {shift_reg[6:0], I2C_SDA};
    end

    // SDA enable
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            sda_en <= 1'b0;
        else if (state == START || state == STOP)
            sda_en <= 1'b1;
        else if (state == ADDR || state == WDATA)
            sda_en <= 1'b1;
        else if (state == ACK || state == RDATA)
            sda_en <= 1'b0;
    end

    // SDA output
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            sda <= 1'b1;
        else if (sda_en)
            sda <= (state == START) ? 1'b0 : (state == STOP) ? 1'b1 : shift_reg[7];
        else if (state == ACK)
            sda <= 1'b0; // Master sends ACK (low)
    end

    // I2C_SCL output
    assign I2C_SCL = scl;

    // I2C_SDA bidirectional handling
    assign I2C_SDA = sda_en ? sda : 1'bz;

    // Data output
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            data_out <= '0;
        else if (state == RDATA && scl && ~scl_en)
            data_out <= {data_out[6:0], I2C_SDA};
    end

    // Busy signal
    assign busy = (state != IDLE);

    // Module enable signal
    assign I2C_En = (state != IDLE);

endmodule