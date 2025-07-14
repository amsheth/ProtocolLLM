module I2C_driver (
    input  logic        clk,         // System clock
    input  logic        rst,         // Asynchronous reset, active high
    input  logic        I2C_Start,   // Initiate transaction
    input  logic        RW,          // 0=write, 1=read
    input  logic [6:0]  slave_addr,  // 7-bit I2C slave address
    input  logic [7:0]  data_in,     // Data to write
    inout  logic        I2C_SDA,     // I2C data line (bidirectional)
    output logic        I2C_SCL,     // I2C clock line
    output logic [7:0]  data_out,    // Data read from slave
    output logic        I2C_En,      // Enable flag
    output logic        busy         // Transaction busy
);

    // *** PARAMETERS ***
    parameter CLK_FREQ_HZ = 50_000_000;  // Input clock
    parameter I2C_FREQ_HZ = 100_000;     // I2C SCL frequency
    localparam SCL_DIV = CLK_FREQ_HZ / (I2C_FREQ_HZ * 4); // 4 phases per SCL

    // *** STATES ***
    typedef enum logic [3:0] {
        IDLE,
        START,
        ADDR,
        ADDR_ACK,
        WRITE,
        WRITE_ACK,
        RESTART,
        READ,
        READ_ACK,
        STOP,
        DONE
    } state_t;

    state_t    state, next_state;

    // *** REGISTERS ***
    logic [15:0] clk_cnt;
    logic [1:0]  scl_phase;         // 0-3: 4 phases per SCL
    logic        scl_int;           // internal SCL
    logic        sda_out;
    logic        sda_oen;           // '0' = drive sda_out, '1' = release line
    logic [7:0]  tx_byte;
    logic [7:0]  rx_byte;
    logic [3:0]  bit_cnt;
    logic        ack_bit;
    logic        sda_in_sync0, sda_in_sync1;
    wire         sda_in;

    // *** SYNCHRONIZE and SENSE SDA INPUT (simulate open-drain on output) ***
    assign sda_in = I2C_SDA;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sda_in_sync0 <= 1'b1;
            sda_in_sync1 <= 1'b1;
        end else begin
            sda_in_sync0 <= I2C_SDA;
            sda_in_sync1 <= sda_in_sync0;
        end
    end

    // *** GENERATE PHY SCL (open-drain) ***
    assign I2C_SCL = (state == IDLE || state == DONE) ? 1'b1 : scl_int;

    // *** I2C DATA LINE OPEN-DRAIN EMULATION ***
    assign I2C_SDA = (sda_oen) ? 1'bz : sda_out;

    // *** BUSY/ENABLE MARKERS ***
    assign busy   = (state != IDLE && state != DONE);
    assign I2C_En = busy;

    // *** OUTPUT CAPTURE ***
    assign data_out = rx_byte;

    // *** CLOCK DIVIDER for 4-phase SCL (0: SDA valid, 1: SCL rising, 2: SDA valid, 3: SCL falling) ***
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_cnt  <= '0;
            scl_phase<= 2'd0;
            scl_int  <= 1'b1;
        end else if (busy) begin
            if (clk_cnt == SCL_DIV-1) begin
                clk_cnt   <= 0;
                scl_phase <= scl_phase + 2'd1;
                if (scl_phase == 2'd1)    scl_int <= 1'b1; // Rising edge
                else if (scl_phase == 2'd3) scl_int <= 1'b0; // Falling edge
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end else begin
            clk_cnt   <= 0;
            scl_int   <= 1'b1;
            scl_phase <= 2'd0;
        end
    end

    // *** MAIN STATE MACHINE ***
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            tx_byte   <= 8'd0;
            rx_byte   <= 8'd0;
            bit_cnt   <= 4'd0;
            sda_out   <= 1'b1;
            sda_oen   <= 1'b1;
            ack_bit   <= 1'b1;
        end else begin
            state <= next_state;

            // Output controls
            case (state)
            //----------------------------------------------------------------------
            IDLE: begin
                sda_oen <= 1'b1;
                sda_out <= 1'b1;
                if (I2C_Start) begin
                    tx_byte <= {slave_addr, RW};
                end
            end
            //----------------------------------------------------------------------
            START: begin
                // Generate start: SDA falls while SCL is high
                if (scl_phase == 2'd0) begin
                    sda_out <= 1'b0;
                    sda_oen <= 1'b0;
                end
            end
            //----------------------------------------------------------------------
            ADDR: begin
                // Send address+R/W
                if (scl_phase == 2'd0) begin
                    sda_out <= tx_byte[7];
                    sda_oen <= 1'b0;
                end
                if (scl_phase == 2'd3) begin
                    tx_byte <= {tx_byte[6:0], 1'b0};
                    bit_cnt <= bit_cnt + 1;
                end
            end
            //----------------------------------------------------------------------
            ADDR_ACK: begin
                // Release SDA for ACK
                if (scl_phase == 2'd0) begin
                    sda_oen <= 1'b1; // Release SDA
                end
                if (scl_phase == 2'd1) begin
                    ack_bit <= sda_in_sync1;
                end
            end
            //----------------------------------------------------------------------
            WRITE: begin
                // Send data byte
                if (scl_phase == 2'd0) begin
                    sda_out <= data_in[7-bit_cnt];
                    sda_oen <= 1'b0;
                end
                if (scl_phase == 2'd3) begin
                    if (bit_cnt != 4'd7) bit_cnt <= bit_cnt + 1;
                end
            end
            //----------------------------------------------------------------------
            WRITE_ACK: begin
                // Release SDA for ACK
                if (scl_phase == 2'd0) begin
                    sda_oen <= 1'b1;
                end
                if (scl_phase == 2'd1) begin
                    ack_bit <= sda_in_sync1;
                end
            end
            //----------------------------------------------------------------------
            RESTART: begin
                // Generate repeated start (for read transactions)
                if (scl_phase == 2'd0) begin
                    sda_out <= 1'b1;
                    sda_oen <= 1'b0;
                end
                if (scl_phase == 2'd1) begin
                    sda_out <= 1'b0;
                end
            end
            //----------------------------------------------------------------------
            READ: begin
                // Receive data byte
                if (scl_phase == 2'd0) begin
                    sda_oen <= 1'b1;
                end
                if (scl_phase == 2'd1) begin
                    rx_byte[7-bit_cnt] <= sda_in_sync1;
                end
                if (scl_phase == 2'd3) begin
                    if (bit_cnt != 4'd7) bit_cnt <= bit_cnt + 1;
                end
            end
            //----------------------------------------------------------------------
            READ_ACK: begin
                // Send NACK (last byte; ACK for multi byte but single here)
                if (scl_phase == 2'd0) begin
                    sda_out <= 1'b1; // NACK for single byte
                    sda_oen <= 1'b0;
                end
            end
            //----------------------------------------------------------------------
            STOP: begin
                // Generate stop: SDA rises while SCL is high
                if (scl_phase == 2'd0) begin
                    sda_out <= 1'b0;
                    sda_oen <= 1'b0;
                end
                if (scl_phase == 2'd1) begin
                    sda_out <= 1'b1;
                end
                if (scl_phase == 2'd2) begin
                    sda_oen <= 1'b1;
                end
            end
            //----------------------------------------------------------------------
            DONE: begin
                sda_oen <= 1'b1;
                sda_out <= 1'b1;
            end
            //----------------------------------------------------------------------
            default:;
            endcase
        end
    end

    // *** NEXT STATE LOGIC ***
    always_comb begin
        next_state = state;
        case (state)
        //---------------------------------------------------------
        IDLE:
            if (I2C_Start) next_state = START;
        //---------------------------------------------------------
        START:
            if (scl_phase == 2'd2) next_state = ADDR, bit_cnt = 0;
        //---------------------------------------------------------
        ADDR:
            if (bit_cnt == 4'd7 && scl_phase == 2'd3) next_state = ADDR_ACK;
        //---------------------------------------------------------
        ADDR_ACK:
            if (scl_phase == 2'd2) begin
                if (ack_bit == 1'b0) // ACK received
                    next_state = (RW) ? RESTART : WRITE, bit_cnt = 0;
                else
                    next_state = STOP; // NACK: abort
            end
        //---------------------------------------------------------
        WRITE:
            if (bit_cnt == 4'd7 && scl_phase == 2'd3) next_state = WRITE_ACK;
        //---------------------------------------------------------
        WRITE_ACK:
            if (scl_phase == 2'd2) begin
                if (ack_bit == 1'b0) // ACK received
                    next_state = STOP;
                else
                    next_state = STOP; // NACK: abort
            end
        //---------------------------------------------------------
        RESTART:
            if (scl_phase == 2'd2) begin
                next_state = ADDR, bit_cnt = 0, tx_byte = {slave_addr, 1'b1};
            end
        //---------------------------------------------------------
        READ:
            if (bit_cnt == 4'd7 && scl_phase == 2'd3) next_state = READ_ACK;
        //---------------------------------------------------------
        READ_ACK:
            if (scl_phase == 2'd2) next_state = STOP;
        //---------------------------------------------------------
        STOP:
            if (scl_phase == 2'd2) next_state = DONE;
        //---------------------------------------------------------
        DONE:
            next_state = IDLE;
        //---------------------------------------------------------
        default:;
        endcase
    end

endmodule