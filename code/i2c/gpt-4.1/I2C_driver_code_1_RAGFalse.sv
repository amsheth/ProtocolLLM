module I2C_driver(
    input  logic        clk,         // System clock
    input  logic        rst,         // Asynchronous reset
    input  logic        I2C_Start,   // Initiate a transaction when high
    input  logic        RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [9:0]  slave_addr,  // 10-bit I2C slave address
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

    // I2C SCL generation (4 phases: low, rising, high, falling)
    typedef enum logic [1:0] {SCL_LOW, SCL_RISE, SCL_HIGH, SCL_FALL} scl_phase_t;
    scl_phase_t scl_phase;
    logic scl_int; // Internal SCL

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
        ADDR10_H,   // Send 1st address byte (11110XX0)
        ADDR10_L,   // Send 2nd address byte (8 LSBs)
        ADDR_ACK1,
        ADDR_ACK2,
        DATA_WR,
        DATA_WR_ACK,
        DATA_RD,
        DATA_RD_ACK,
        STOP,
        DONE
    } state_t;

    state_t state, next_state;

    // Internal signals
    logic [7:0] tx_byte;
    logic [7:0] rx_byte;
    logic [3:0] bit_cnt;
    logic sda_out, sda_oe;
    logic sda_in;
    logic ack_bit;
    logic start_latch;
    logic [7:0] data_out_reg;

    // Bidirectional SDA handling
    assign I2C_SDA = sda_oe ? sda_out : 1'bz;
    assign sda_in  = I2C_SDA;

    // Output assignments
    assign data_out = data_out_reg;
    assign I2C_En   = (state != IDLE);
    assign busy     = (state != IDLE);

    // FSM Sequential
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            bit_cnt      <= 0;
            tx_byte      <= 0;
            rx_byte      <= 0;
            sda_out      <= 1;
            sda_oe       <= 1;
            ack_bit      <= 0;
            start_latch  <= 0;
            data_out_reg <= 0;
        end else begin
            if (scl_tick) begin
                state <= next_state;
            end
        end
    end

    // FSM Combinational
    always_comb begin
        // Default values
        next_state = state;
        sda_oe     = 1;
        sda_out    = 1;

        case (state)
            IDLE: begin
                sda_out = 1;
                sda_oe  = 1;
                if (I2C_Start && !start_latch) begin
                    next_state = START;
                end
            end

            START: begin
                // Generate start: SDA goes low while SCL is high
                sda_out = 0;
                sda_oe  = 1;
                if (scl_phase == SCL_HIGH) begin
                    next_state = ADDR10_H;
                    bit_cnt    = 7;
                    // 1st address byte: 11110XX0 (10-bit addressing, R/W=0)
                    tx_byte = {5'b11110, slave_addr[9:8], 1'b0};
                end
            end

            ADDR10_H: begin
                // Send 1st address byte (MSB first)
                sda_out = tx_byte[bit_cnt];
                sda_oe  = 1;
                if (scl_phase == SCL_LOW) begin
                    if (bit_cnt == 0)
                        next_state = ADDR_ACK1;
                    else
                        bit_cnt = bit_cnt - 1;
                end
            end

            ADDR_ACK1: begin
                // Release SDA for ACK
                sda_oe = 0;
                if (scl_phase == SCL_HIGH) begin
                    ack_bit = sda_in;
                    next_state = ADDR10_L;
                    bit_cnt = 7;
                    // 2nd address byte: 8 LSBs of address
                    tx_byte = slave_addr[7:0];
                end
            end

            ADDR10_L: begin
                // Send 2nd address byte (MSB first)
                sda_out = tx_byte[bit_cnt];
                sda_oe  = 1;
                if (scl_phase == SCL_LOW) begin
                    if (bit_cnt == 0)
                        next_state = ADDR_ACK2;
                    else
                        bit_cnt = bit_cnt - 1;
                end
            end

            ADDR_ACK2: begin
                // Release SDA for ACK
                sda_oe = 0;
                if (scl_phase == SCL_HIGH) begin
                    ack_bit = sda_in;
                    if (RW == 0) begin
                        // Write operation
                        next_state = DATA_WR;
                        bit_cnt = 7;
                        tx_byte = data_in;
                    end else begin
                        // Read operation: repeated start
                        next_state = START;
                        // For repeated start, set up 1st address byte with R/W=1
                        tx_byte = {5'b11110, slave_addr[9:8], 1'b1};
                        bit_cnt = 7;
                    end
                end
            end

            DATA_WR: begin
                // Send data byte (MSB first)
                sda_out = tx_byte[bit_cnt];
                sda_oe  = 1;
                if (scl_phase == SCL_LOW) begin
                    if (bit_cnt == 0)
                        next_state = DATA_WR_ACK;
                    else
                        bit_cnt = bit_cnt - 1;
                end
            end

            DATA_WR_ACK: begin
                // Release SDA for ACK
                sda_oe = 0;
                if (scl_phase == SCL_HIGH) begin
                    ack_bit = sda_in;
                    next_state = STOP;
                end
            end

            DATA_RD: begin
                // Receive data byte (MSB first)
                sda_oe = 0;
                if (scl_phase == SCL_HIGH) begin
                    rx_byte[bit_cnt] = sda_in;
                    if (bit_cnt == 0)
                        next_state = DATA_RD_ACK;
                    else
                        bit_cnt = bit_cnt - 1;
                end
            end

            DATA_RD_ACK: begin
                // Send NACK after last byte
                sda_out = 1; // NACK
                sda_oe  = 1;
                if (scl_phase == SCL_LOW) begin
                    data_out_reg = rx_byte;
                    next_state = STOP;
                end
            end

            STOP: begin
                // Generate stop: SDA goes high while SCL is high
                sda_out = 0;
                sda_oe  = 1;
                if (scl_phase == SCL_HIGH) begin
                    sda_out = 1;
                    sda_oe  = 1;
                    next_state = DONE;
                end
            end

            DONE: begin
                sda_out = 1;
                sda_oe  = 1;
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase

        // For read operation, after repeated start and address, go to DATA_RD
        if (state == ADDR_ACK1 && RW == 1 && scl_phase == SCL_HIGH) begin
            next_state = DATA_RD;
            bit_cnt = 7;
        end
    end

    // Latch start signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            start_latch <= 0;
        else if (I2C_Start)
            start_latch <= 1;
        else if (state == IDLE)
            start_latch <= 0;
    end

endmodule