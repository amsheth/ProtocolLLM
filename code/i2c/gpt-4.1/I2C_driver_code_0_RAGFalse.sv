module I2C_driver(
    input  logic        clk,         // System clock
    input  logic        rst,         // Asynchronous reset
    input  logic        I2C_Start,   // Initiate a transaction when high
    input  logic        RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [6:0]  slave_addr,  // 7-bit I2C slave address
    input  logic [7:0]  data_in,     // Data to be written (for write transactions)
    inout  logic        I2C_SDA,     // I2C data line (bidirectional)
    output logic        I2C_SCL,     // I2C clock line
    output logic [7:0]  data_out,    // Data received from slave (for read transactions)
    output logic        I2C_En,      // Module enable signal (active during transaction)
    output logic        busy         // Indicates the module is busy with a transaction
);

    // Parameters
    parameter SYS_CLK_FREQ = 50_000_000; // System clock frequency in Hz
    parameter I2C_FREQ     = 100_000;    // I2C SCL frequency in Hz

    // Clock Divider
    localparam integer DIVIDER = SYS_CLK_FREQ / (I2C_FREQ * 4); // 4 phases per SCL
    logic [$clog2(DIVIDER)-1:0] clk_div_cnt;
    logic scl_tick; // SCL phase tick

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_cnt <= 0;
            scl_tick    <= 0;
        end else begin
            if (clk_div_cnt == DIVIDER-1) begin
                clk_div_cnt <= 0;
                scl_tick    <= 1;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1;
                scl_tick    <= 0;
            end
        end
    end

    // SCL generation (4 phases: low, rising, high, falling)
    typedef enum logic [1:0] {SCL_LOW, SCL_RISE, SCL_HIGH, SCL_FALL} scl_phase_t;
    scl_phase_t scl_phase;
    logic scl_int;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scl_phase <= SCL_HIGH;
            scl_int   <= 1;
        end else if (scl_tick) begin
            case (scl_phase)
                SCL_LOW:  begin scl_phase <= SCL_RISE;  scl_int <= 0; end
                SCL_RISE: begin scl_phase <= SCL_HIGH;  scl_int <= 1; end
                SCL_HIGH: begin scl_phase <= SCL_FALL;  scl_int <= 1; end
                SCL_FALL: begin scl_phase <= SCL_LOW;   scl_int <= 0; end
            endcase
        end
    end
    assign I2C_SCL = scl_int;

    // I2C FSM States
    typedef enum logic [3:0] {
        IDLE,
        START,
        ADDR,
        ADDR_ACK,
        WRITE,
        WRITE_ACK,
        READ,
        READ_ACK,
        STOP,
        DONE
    } state_t;

    state_t state, next_state;

    // Internal signals
    logic [3:0] bit_cnt;
    logic [7:0] shifter;
    logic       sda_out_en; // 1: drive SDA, 0: release (input)
    logic       sda_out;    // Value to drive on SDA
    logic [7:0] rx_data;
    logic       ack_bit;
    logic       sda_in_sync;
    logic       start_latch;
    logic       busy_int;
    logic       I2C_En_int;

    // Synchronize SDA input
    always_ff @(posedge clk) begin
        sda_in_sync <= I2C_SDA;
    end

    // Bidirectional SDA control
    assign I2C_SDA = sda_out_en ? sda_out : 1'bz;

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            bit_cnt    <= 0;
            shifter    <= 0;
            sda_out_en <= 1;
            sda_out    <= 1;
            rx_data    <= 0;
            ack_bit    <= 0;
            start_latch<= 0;
            busy_int   <= 0;
            I2C_En_int <= 0;
        end else begin
            if (I2C_Start && !busy_int)
                start_latch <= 1;
            else if (state == START)
                start_latch <= 0;

            if (scl_tick) begin
                case (state)
                    IDLE: begin
                        sda_out_en <= 1;
                        sda_out    <= 1;
                        busy_int   <= 0;
                        I2C_En_int <= 0;
                        if (start_latch) begin
                            state   <= START;
                            busy_int<= 1;
                            I2C_En_int <= 1;
                        end
                    end
                    START: begin
                        // Generate start: SDA goes low while SCL is high
                        sda_out_en <= 1;
                        sda_out    <= 0;
                        state      <= ADDR;
                        bit_cnt    <= 7;
                        shifter    <= {slave_addr, RW};
                    end
                    ADDR: begin
                        // Send address + RW bit, MSB first
                        sda_out_en <= 1;
                        sda_out    <= shifter[bit_cnt];
                        if (scl_phase == SCL_FALL) begin
                            if (bit_cnt == 0)
                                state <= ADDR_ACK;
                            else
                                bit_cnt <= bit_cnt - 1;
                        end
                    end
                    ADDR_ACK: begin
                        // Release SDA, sample ACK from slave
                        sda_out_en <= 0;
                        if (scl_phase == SCL_HIGH) begin
                            ack_bit <= sda_in_sync;
                        end
                        if (scl_phase == SCL_FALL) begin
                            if (RW)
                                state <= READ;
                            else
                                state <= WRITE;
                            bit_cnt <= 7;
                            shifter<= data_in;
                        end
                    end
                    WRITE: begin
                        // Send data byte, MSB first
                        sda_out_en <= 1;
                        sda_out    <= shifter[bit_cnt];
                        if (scl_phase == SCL_FALL) begin
                            if (bit_cnt == 0)
                                state <= WRITE_ACK;
                            else
                                bit_cnt <= bit_cnt - 1;
                        end
                    end
                    WRITE_ACK: begin
                        // Release SDA, sample ACK from slave
                        sda_out_en <= 0;
                        if (scl_phase == SCL_HIGH) begin
                            ack_bit <= sda_in_sync;
                        end
                        if (scl_phase == SCL_FALL) begin
                            state <= STOP;
                        end
                    end
                    READ: begin
                        // Release SDA, sample data from slave
                        sda_out_en <= 0;
                        if (scl_phase == SCL_HIGH) begin
                            rx_data[bit_cnt] <= sda_in_sync;
                        end
                        if (scl_phase == SCL_FALL) begin
                            if (bit_cnt == 0)
                                state <= READ_ACK;
                            else
                                bit_cnt <= bit_cnt - 1;
                        end
                    end
                    READ_ACK: begin
                        // Send NACK (1) after last byte
                        sda_out_en <= 1;
                        sda_out    <= 1; // NACK
                        if (scl_phase == SCL_FALL) begin
                            state <= STOP;
                        end
                    end
                    STOP: begin
                        // Generate stop: SDA goes high while SCL is high
                        sda_out_en <= 1;
                        sda_out    <= 0;
                        if (scl_phase == SCL_HIGH) begin
                            sda_out <= 1;
                            state   <= DONE;
                        end
                    end
                    DONE: begin
                        sda_out_en <= 1;
                        sda_out    <= 1;
                        busy_int   <= 0;
                        I2C_En_int <= 0;
                        state      <= IDLE;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end

    // Output assignments
    assign busy     = busy_int;
    assign I2C_En   = I2C_En_int;
    assign data_out = rx_data;

endmodule