module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
    input  logic       I2C_Start,   // Initiate a transaction when high input
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [6:0] slave_addr,  // 7-bit I2C slave address
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

    // Clock divider parameters
    parameter int CLK_DIV = 100;  // Adjust this to get the desired SCL frequency from clk

    // State machine states
    typedef enum logic [3:0] {
        IDLE, START, ADDR_SEND, R_W_SEND, DATA_SEND, DATA_RECEIVE,
        ACK_NACK_CHECK, STOP, ERROR
    } state_t;

    state_t current_state, next_state;
    logic [7:0] bit_cnt;  // Bit counter for data/address transfer
    logic [7:0] data_reg; // Register to hold the byte being sent/received
    logic scl_en;         // Enable signal for SCL generation
    logic scl_pulse;      // Pulse signal for SCL transitions
    logic scl_rst_cnt;    // Reset counter for SCL pulse generation
    logic sda_out, sda_dir;  // SDA output and direction control

    // Clock divider logic
    logic [7:0] clk_div_counter;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_counter <= '0;
            scl_pulse <= 0;
        end else if (scl_en && !busy) begin
            if (clk_div_counter == CLK_DIV - 1) begin
                clk_div_counter <= '0;
                scl_pulse <= ~scl_pulse; // Toggle SCL pulse
            end else begin
                clk_div_counter <= clk_div_counter + 1;
            end
        end
    end

    assign I2C_SCL = scl_pulse;

    // State machine to handle I2C transactions
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        scl_en = 0;
        sda_out = 'Z; // Default to high-impedance for SDA
        sda_dir = 1'b1; // Default direction is input (tri-state)
        busy = 1'b1;

        case (current_state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START;
                    scl_en = 1;
                    busy = 1'b0;
                end else begin
                    busy = 1'b0;
                end
            end

            START: begin
                sda_dir = 1'b0; // SDA is output
                sda_out = 0;    // Generate start condition
                if (scl_pulse) begin
                    scl_rst_cnt = 1;
                    next_state = ADDR_SEND;
                end
            end

            ADDR_SEND: begin
                data_reg = {slave_addr, RW}; // Load address and R/W bit
                scl_en = 1;
                sda_dir = 1'b0; // SDA is output
                if (scl_pulse) begin
                    if (bit_cnt < 8) begin
                        sda_out = data_reg[7 - bit_cnt]; // Send bits MSB first
                        bit_cnt++;
                    end else begin
                        next_state = ACK_NACK_CHECK;
                        scl_rst_cnt = 1;
                        bit_cnt = '0;
                    end
                end
            end

            R_W_SEND: begin
                data_reg = RW; // Load R/W bit
                scl_en = 1;
                sda_dir = 1'b0; // SDA is output
                if (scl_pulse) begin
                    if (bit_cnt < 8) begin
                        sda_out = data_reg[7 - bit_cnt]; // Send bits MSB first
                        bit_cnt++;
                    end else begin
                        next_state = ACK_NACK_CHECK;
                        scl_rst_cnt = 1;
                        bit_cnt = '0;
                    end
                end
            end

            DATA_SEND: begin
                data_reg = data_in; // Load data to send
                scl_en = 1;
                sda_dir = 1'b0; // SDA is output
                if (scl_pulse) begin
                    if (bit_cnt < 8) begin
                        sda_out = data_reg[7 - bit_cnt]; // Send bits MSB first
                        bit_cnt++;
                    end else begin
                        next_state = ACK_NACK_CHECK;
                        scl_rst_cnt = 1;
                        bit_cnt = '0;
                    end
                end
            end

            DATA_RECEIVE: begin
                scl_en = 1;
                sda_dir = 1'b1; // SDA is input
                if (scl_pulse) begin
                    if (bit_cnt < 8) begin
                        data_out[7 - bit_cnt] = I2C_SDA; // Receive bits MSB first
                        bit_cnt++;
                    end else begin
                        next_state = STOP;
                        scl_rst_cnt = 1;
                        bit_cnt = '0;
                    end
                end
            end

            ACK_NACK_CHECK: begin
                scl_en = 1;
                sda_dir = 1'b1; // SDA is input
                if (scl_pulse) begin
                    if (I2C_SDA) begin
                        next_state = ERROR; // NACK received
                    end else begin
                        if (!RW)
                            next_state = DATA_SEND;
                        else
                            next_state = DATA_RECEIVE;
                    end
                    scl_rst_cnt = 1;
                end
            end

            STOP: begin
                sda_dir = 1'b0; // SDA is output
                sda_out = 0;    // Set SDA low
                if (scl_pulse) begin
                    next_state = IDLE;
                    scl_rst_cnt = 1;
                    busy = 1'b0;
                end else begin
                    sda_out = 1; // Release SDA to high
                end
            end

            ERROR: begin
                // Handle error state
                next_state = IDLE;
                scl_rst_cnt = 1;
                busy = 1'b0;
            end

            default:
                next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            bit_cnt <= '0;
        else if (scl_rst_cnt)
            bit_cnt <= '0;
    end

endmodule