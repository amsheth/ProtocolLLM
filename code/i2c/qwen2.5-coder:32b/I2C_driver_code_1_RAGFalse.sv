module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
    input  logic       I2C_Start,   // Initiate a transaction when high input
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read input
    input  logic [9:0] slave_addr,  // 10-bit I2C slave address input
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

// Constants for I2C timing and clock division
localparam CLK_DIV = 100;          // Example clock divider value for 100MHz clk -> 1MHz SCL
localparam BIT_WIDTH = 9;           // Number of bits to transfer (including start/stop)
localparam ADDR_WIDTH = 10;         // Width of the slave address

// Clock divider and state machine signals
logic [$clog2(CLK_DIV)-1:0] clk_div_cnt;
logic scl_clk;

// State machine states
typedef enum logic [3:0] {
    IDLE,
    START_COND,
    ADDR_TRANS,
    DATA_TRANS,
    STOP_COND,
    DONE
} i2c_state_t;

i2c_state_t state, next_state;

// Internal signals
logic [ADDR_WIDTH-1:0] addr_reg;
logic [7:0] data_reg;
logic bit_cnt_done;
logic bit_cnt;
logic start_cond_done;
logic stop_cond_done;
logic write_ack_error;
logic read_nack_error;

assign I2C_En = (state != IDLE);
assign busy = (state != IDLE);

// Clock divider
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        clk_div_cnt <= '0;
        scl_clk <= 1'b1; // Start with SCL high
    end else begin
        if (clk_div_cnt == CLK_DIV-1) begin
            clk_div_cnt <= '0;
            scl_clk <= ~scl_clk; // Toggle SCL
        end else begin
            clk_div_cnt <= clk_div_cnt + 1;
        end
    end
end

// I2C_SCL output assignment
assign I2C_SCL = scl_clk;

// State machine transition logic
always_ff @(posedge scl_clk or posedge rst) begin
    if (rst)
        state <= IDLE;
    else
        state <= next_state;
end

// State machine combinational logic
always_comb begin
    next_state = state;
    case (state)
        IDLE: begin
            if (I2C_Start)
                next_state = START_COND;
        end
        START_COND: begin
            if (start_cond_done)
                next_state = ADDR_TRANS;
        end
        ADDR_TRANS: begin
            if (bit_cnt_done) begin
                if (RW == 1'b0) // Write operation
                    next_state = DATA_TRANS;
                else if (RW == 1'b1) // Read operation
                    next_state = DATA_TRANS;
            end
        end
        DATA_TRANS: begin
            if (bit_cnt_done)
                if (write_ack_error || read_nack_error)
                    next_state = STOP_COND; // Handle error conditions
                else if (RW == 1'b0 && bit_cnt < (ADDR_WIDTH + 8)) // More data to write
                    next_state = DATA_TRANS;
                else if (RW == 1'b1 && bit_cnt < 2*(ADDR_WIDTH + 8)) // More data to read
                    next_state = DATA_TRANS;
                else
                    next_state = STOP_COND; // All data transferred
        end
        STOP_COND: begin
            if (stop_cond_done)
                next_state = DONE;
        end
        DONE: begin
            next_state = IDLE;
        end
    endcase
end

// Start condition generation
logic start_cond_gen;

always_ff @(posedge scl_clk or posedge rst) begin
    if (rst) begin
        start_cond_done <= 1'b0;
        I2C_SDA <= 1'bz; // Tri-state SDA for bidirectional use
    end else begin
        case (state)
            START_COND: begin
                if (!scl_clk && I2C_SDA == 1'b1) begin // Start condition is falling edge of SCL with SDA high to low
                    start_cond_gen = 1'b1;
                    I2C_SDA <= 1'b0; // Pull SDA low for start condition
                end else if (start_cond_gen && scl_clk) begin // Wait for rising edge of SCL after start condition generation
                    start_cond_done <= 1'b1;
                    I2C_SDA <= 1'bz; // Release SDA
                end
            end
            default: begin
                start_cond_gen = 1'b0;
                start_cond_done <= 1'b0;
            end
        endcase
    end
end

// Stop condition generation
always_ff @(posedge scl_clk or posedge rst) begin
    if (rst)
        stop_cond_done <= 1'b0;
    else if (state == STOP_COND && !scl_clk && I2C_SDA == 1'b0) // Generate stop condition on falling edge of SCL with SDA low to high
        stop_cond_done <= 1'b0;
    else if (stop_cond_done && scl_clk)
        stop_cond_done <= 1'b1; // Wait for rising edge of SCL after stop condition generation
end

// Bit counter logic
always_ff @(posedge scl_clk or posedge rst) begin
    if (rst || state == IDLE)
        bit_cnt <= '0;
    else if (!scl_clk && bit_cnt < BIT_WIDTH)
        bit_cnt <= bit_cnt + 1;
    else
        bit_cnt <= '0; // Reset after all bits are transferred
end

// Data transfer logic
always_ff @(posedge scl_clk or posedge rst) begin
    if (rst || state == IDLE) begin
        addr_reg <= slave_addr;
        data_reg <= data_in;
        write_ack_error <= 1'b0;
        read_nack_error <= 1'b0;
        bit_cnt_done <= 1'b0;
        I2C_SDA <= 1'bz; // Tri-state SDA for bidirectional use
    end else begin
        case (state)
            ADDR_TRANS, DATA_TRANS: begin
                if (!scl_clk) begin // On falling edge of SCL, output data bit or ACK/NACK
                    if (bit_cnt < ADDR_WIDTH)
                        I2C_SDA <= addr_reg[ADDR_WIDTH-1-bit_cnt]; // Output address bits MSB first
                    else if (RW == 1'b0 && bit_cnt < (ADDR_WIDTH + 8))
                        I2C_SDA <= data_reg[7-(bit_cnt - ADDR_WIDTH)]; // Output data bits for write operation MSB first
                    else if (RW == 1'b1) begin
                        if (bit_cnt == ADDR_WIDTH)
                            I2C_SDA <= 1'bz; // Release SDA to input mode for ACK/NACK during read operation
                        else if (bit_cnt > ADDR_WIDTH && bit_cnt < (ADDR_WIDTH + 9))
                            data_reg[7-(bit_cnt - ADDR_WIDTH - 1)] <= I2C_SDA; // Capture received data bits LSB first
                    end

                    if ((RW == 1'b0 || RW == 1'b1) && bit_cnt == BIT_WIDTH-1)
                        bit_cnt_done <= 1'b1;
                end else begin // On rising edge of SCL, read ACK/NACK or release SDA for next bit
                    if (bit_cnt == ADDR_WIDTH-1 && RW == 1'b0) // Write operation, check ACK from slave on last address bit clock cycle
                        write_ack_error <= I2C_SDA;
                    else if (RW == 1'b1) begin // Read operation, output ACK/NACK to slave
                        if (bit_cnt == ADDR_WIDTH-1)
                            I2C_SDA <= 1'b0; // Send ACK for address reception
                        else if (bit_cnt == BIT_WIDTH - 2) // Last data bit clock cycle
                            I2C_SDA <= 1'b1; // Send NACK to indicate end of read operation
                    end

                    bit_cnt_done <= 1'b0;
                end
            end
            default: begin
                bit_cnt_done <= 1'b0;
                I2C_SDA <= 1'bz; // Tri-state SDA for bidirectional use
            end
        endcase
    end
end

// Output received data (for read operation)
assign output_data = RW == 1'b1 ? data_reg : 'z;

endmodule