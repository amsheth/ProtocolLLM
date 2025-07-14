module I2C_driver (
    input  logic        clk,          // System clock
    input  logic        rst,          // Asynchronous reset
    input  logic        I2C_Start,    // Start transaction
    input  logic        RW,           // 0: Write, 1: Read
    input  logic [9:0]  slave_addr,   // 10-bit slave address
    input  logic [7:0]  data_in,      // Data to write
    inout  logic        I2C_SDA,      // I2C Data Line (bidirectional)
    output logic        I2C_SCL,      // I2C Clock Line
    output logic [7:0]  data_out,     // Data read from slave
    output logic        I2C_En,       // Enable signal
    output logic        busy          // Busy flag
);

    // I2C clock divider (modify I2C_DIVIDER as needed for desired SCL frequency)
    parameter I2C_DIVIDER = 250; // Suppose clk=100MHz -> ~400kHz SCL
    logic [$clog2(I2C_DIVIDER)-1:0] clk_cnt;
    logic scl_int, scl_en;
    logic scl_rising, scl_falling;

    // Bidirectional SDA buffering
    logic sda_out, sda_oe, sda_in;
    assign I2C_SDA = sda_oe ? sda_out : 1'bz;
    assign sda_in  = I2C_SDA;

    // SCL: Open-drain, drive low or release to z
    logic scl_oe, scl_out;
    assign I2C_SCL = scl_oe ? scl_out : 1'bz;

    // State machine
    typedef enum logic [3:0] {
        IDLE,
        START,
        SEND_ADDR0,    // Send 1st address byte (9:8 + 7 bits + MSB R/W)
        ADDR_ACK0,
        SEND_ADDR1,    // Send 2nd address byte (7:0)
        ADDR_ACK1,
        WRITE_DATA,
        WRITE_ACK,
        READ_DATA,
        READ_ACK,      
        STOP,
        DONE
    } state_t;
    state_t state, next_state;

    // Internal registers
    logic [3:0] bit_cnt;
    logic [7:0] shift_reg;
    logic ack_bit, ack_capture;
    logic [7:0] data_read;
    logic transaction_active;

    //-------------------
    // Clock divider for SCL
    //-------------------
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            clk_cnt <= 0;
            scl_en  <= 0;
            scl_int <= 1'b1; // SCL idle is HI
        end
        else if (transaction_active) begin
            if(clk_cnt == I2C_DIVIDER/2-1) begin
                clk_cnt <= 0;
                scl_int <= ~scl_int;
                scl_en  <= 1'b1;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
                scl_en  <= 1'b0;
            end
        end else begin
            scl_int <= 1'b1;
            clk_cnt <= 0;
            scl_en  <= 1'b0;
        end
    end

    assign scl_rising  = scl_en && scl_int;
    assign scl_falling = scl_en && ~scl_int;

    //-------------------
    // Main State Machine
    //-------------------
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            state   <= IDLE;
            busy    <= 0;
            I2C_En  <= 0;
            scl_oe  <= 0;
            scl_out <= 1'b1;
            sda_oe  <= 0;
            sda_out <= 1'b1;
            data_out <= 8'h00;
            transaction_active <= 0;
        end
        else begin
            state <= next_state;
            if(next_state != IDLE) busy <= 1;
            else busy <= 0;
            I2C_En <= (next_state != IDLE && next_state != DONE);
        end
    end

    always_comb begin
        next_state = state;
        transaction_active = 0;
        case(state)
        //----------------------------------------
        // Idle/Start condition
        //----------------------------------------
        IDLE: begin
            scl_oe  = 0;        // Release SCL
            scl_out = 1'b1;     // Default is HIGH (z)
            sda_oe  = 0;        // Release SDA
            sda_out = 1'b1;
            data_out = data_read;
            if(I2C_Start) begin
                next_state = START;
            end
        end
        START: begin
            // Generate Start: SDA goes from High to Low while SCL is High
            scl_oe  = 0; scl_out = 1'b1; // Release SCL, keep high
            sda_oe  = 1; sda_out = 1'b0; // Drive SDA LOW
            next_state = SEND_ADDR0;
            transaction_active = 1;
        end
        //----------------------------------------
        // Send Address (10-bit)
        //----------------------------------------
        SEND_ADDR0: begin
            // Send 1st address byte: 11110XXR (first 5 bits are 11110, then addr[9:8], then R/W)
            // [7:3]: 11110, [2:1] slave_addr[9:8], [0] R/W=0 for write,1 for read
            scl_oe  = 1; scl_out = scl_int;
            sda_oe  = 1;

            shift_reg = {5'b11110, slave_addr[9:8], 1'b0}; // R/W=0 for addr, will send R/W on 2nd addr byte for read
            bit_cnt = 4'd7;
            next_state = ADDR_ACK0;
        end
        ADDR_ACK0: begin
            // Wait for ACK from slave after 1st address byte
            scl_oe  = 1; scl_out = scl_int;
            sda_oe  = 0; // Release SDA so slave can send ACK
            if(scl_rising) begin
                ack_capture = sda_in;
                next_state = SEND_ADDR1;
            end
        end
        SEND_ADDR1: begin
            // Send 2nd address byte: [7:1]=addr[7:1], [0]=R/W
            scl_oe  = 1; scl_out = scl_int;
            sda_oe  = 1;
            shift_reg = {slave_addr[7:1], RW};
            bit_cnt = 4'd7;
            next_state = ADDR_ACK1;
        end
        ADDR_ACK1: begin
            // Wait for ACK from slave after 2nd address byte
            scl_oe  = 1; scl_out = scl_int;
            sda_oe  = 0;
            if(scl_rising) begin
                ack_capture = sda_in;
                if(RW == 1'b0)
                    next_state = WRITE_DATA;
                else
                    next_state = READ_DATA;
            end
        end
        //----------------------------------------
        // Write data byte & receive ACK
        //----------------------------------------
        WRITE_DATA: begin
            scl_oe  = 1; scl_out = scl_int;
            sda_oe  = 1;
            shift_reg = data_in;
            bit_cnt = 4'd7;
            next_state = WRITE_ACK;
        end
        WRITE_ACK: begin
            scl_oe  = 1; scl_out = scl_int;
            sda_oe  = 0; // Release for ACK from slave
            if(scl_rising) begin
                ack_capture = sda_in;
                next_state = STOP;
            end
        end
        //----------------------------------------
        // Read data byte & send NACK
        //----------------------------------------
        READ_DATA: begin
            scl_oe  = 1; scl_out = scl_int;
            sda_oe  = 0; // Release SDA for slave to drive
            bit_cnt = 4'd7;
            next_state = READ_ACK;
        end
        READ_ACK: begin
            scl_oe  = 1; scl_out = scl_int;
            sda_oe  = 1; sda_out = 1'b1; // Send NACK
            if(scl_rising) begin
                // capture byte read
                data_read = shift_reg;
                next_state = STOP;
            end
        end
        //----------------------------------------
        // STOP condition
        //----------------------------------------
        STOP: begin
            // Generate stop: SDA low to high while SCL high
            scl_oe = 0; scl_out = 1'b1; // set SCL high
            sda_oe = 1;
            sda_out = 1'b1; // SDA low to high while SCL high
            next_state = DONE;
        end
        DONE: begin
            scl_oe  = 0; scl_out = 1'b1;
            sda_oe  = 0; sda_out = 1'b1;
            data_out = data_read;
            next_state = IDLE;
        end
        default: begin
            next_state = IDLE;
            scl_oe = 0;
            sda_oe = 0;
        end
        endcase
    end

    ////////////////////////////
    // Data shifting
    ////////////////////////////
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            shift_reg <= 8'h00;
            bit_cnt   <= 0;
        end else if (transaction_active && scl_falling) begin
            case(state)
                SEND_ADDR0, SEND_ADDR1, WRITE_DATA: begin
                    if(bit_cnt > 0) begin
                        sda_out  <= shift_reg[7];
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bit_cnt <= bit_cnt - 1;
                    end else begin
                        sda_oe <= 0; // release SDA for ACK
                    end
                end
                READ_DATA: begin
                    if(bit_cnt > 0) begin
                        shift_reg <= {shift_reg[6:0], sda_in};
                        bit_cnt <= bit_cnt - 1;
                    end else begin
                        // Latch last bit
                        shift_reg <= {shift_reg[6:0], sda_in};
                    end
                end
                default:;
            endcase
        end
    end

endmodule