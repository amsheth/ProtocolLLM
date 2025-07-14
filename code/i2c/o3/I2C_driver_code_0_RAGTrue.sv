// ==========================================================
// Simple single-byte I²C master (7-bit addressing)
// ==========================================================
module I2C_driver
#(
    // -----------------------------------------------------------------
    // Change these two parameters to meet any clock / I²C-speed target
    // -----------------------------------------------------------------
    parameter int SYS_CLK_FREQ = 50_000_000,   // Hz – system clock
    parameter int I2C_CLK_FREQ = 100_000       // Hz – SCL frequency
)
(
    input  logic       clk,          // system clock
    input  logic       rst,          // asynchronous reset (active high)

    // user interface ---------------------------------------------------
    input  logic       I2C_Start,    // assert for one cycle to launch a Tx
    input  logic       RW,           // 0 = write, 1 = read
    input  logic [6:0] slave_addr,   // 7-bit address
    input  logic [7:0] data_in,      // byte to write
    inout  tri1        I2C_SDA,      // bidirectional SDA   (tri1 -> pull-up)
    output logic       I2C_SCL,      // SCL generated here
    output logic [7:0] data_out,     // byte received (read transactions)
    output logic       I2C_En,       // ‘1’ while transaction in progress
    output logic       busy          // same as I2C_En
);

    // ===============================================================
    // 1. SCL generator – square wave, high in the IDLE state
    // ===============================================================
    localparam int DIVIDER = SYS_CLK_FREQ / (I2C_CLK_FREQ * 2); // half period
    logic [$clog2(DIVIDER)-1:0] div_cnt;
    logic                        scl_int;
    logic                        scl_half_pulse;

    // divider
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_cnt        <= '0;
            scl_half_pulse <= 1'b0;
        end else begin
            if (div_cnt == DIVIDER-1) begin
                div_cnt        <= '0;
                scl_half_pulse <= 1'b1;             // one-cycle strobe each half period
            end else begin
                div_cnt        <= div_cnt + 1'b1;
                scl_half_pulse <= 1'b0;
            end
        end
    end

    // toggle SCL only when a transfer is active
    always_ff @(posedge clk or posedge rst) begin
        if (rst)                scl_int <= 1'b1;           // idle bus = high
        else if (I2C_En) begin
            if (scl_half_pulse) scl_int <= ~scl_int;
        end else                scl_int <= 1'b1;
    end
    assign I2C_SCL = scl_int;

    // edge detectors for the FSM
    logic scl_prev;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) scl_prev <= 1'b1;
        else     scl_prev <= scl_int;
    end
    wire scl_rise =  scl_int & ~scl_prev;
    wire scl_fall = ~scl_int &  scl_prev;

    // ===============================================================
    // 2. Main FSM
    // ===============================================================
    typedef enum logic [3:0] {
        IDLE,          // wait for I2C_Start
        START_A,       // SDA:1->0 while SCL high
        START_B,       // first SCL low half-cycle
        SEND_BYTE,     // shift out 8 bits (addr or data)
        WAIT_ACK,      // release SDA, sample ACK
        READ_BYTE,     // shift in 8 bits from slave
        SEND_NACK,     // drive NACK (=‘1’) after last read
        STOP_A,        // SDA low while SCL low
        STOP_B,        // SDA 0->1 while SCL high
        DONE           // clean-up, return to IDLE
    } state_t;

    state_t state, next_state;

    // shift register / counters / flags
    logic [7:0] shift;
    logic [2:0] bit_cnt;
    logic       sending_addr;        // ‘1’ while address byte is being sent
    logic       sda_drive_low;       // combinational – drive SDA low?

    // ----------------------------------------------------------------
    // next-state & output combinational logic
    // ----------------------------------------------------------------
    always_comb begin
        next_state    = state;
        sda_drive_low = 1'b0;        // default: release SDA

        unique case (state)
        //------------------------------------------------------------------
        IDLE : begin
            if (I2C_Start) next_state = START_A;
        end
        //------------------------------------------------------------------
        START_A : begin
            sda_drive_low = 1'b1;                 // pull SDA low (START)
            if (scl_fall) next_state = START_B;
        end
        START_B : begin
            sda_drive_low = 1'b1;                 // keep SDA low
            if (scl_fall) next_state = SEND_BYTE;
        end
        //------------------------------------------------------------------
        SEND_BYTE : begin                         // drive MSB first
            sda_drive_low = ~shift[7];            // only 0's are driven
            if (scl_fall) begin
                if (bit_cnt == 3'd0) next_state = WAIT_ACK;
            end
        end
        WAIT_ACK : begin                          // sample on SCL rising edge
            if (scl_rise) begin
                if (sending_addr & RW)          next_state = READ_BYTE; // start reading
                else if (sending_addr & ~RW)    next_state = SEND_BYTE; // send data byte
                else if (~sending_addr & ~RW)   next_state = STOP_A;    // write finished
                else                            next_state = SEND_NACK; // read finished
            end
        end
        //------------------------------------------------------------------
        READ_BYTE : begin                         // SDA released, slave drives
            if (scl_rise) begin
                if (bit_cnt == 3'd0) next_state = SEND_NACK;
            end
        end
        SEND_NACK : begin                         // master sends NACK (=‘1’ -> release)
            // nothing driven → sda_drive_low stays 0
            if (scl_fall) next_state = STOP_A;
        end
        //------------------------------------------------------------------
        STOP_A : begin
            sda_drive_low = 1'b1;                 // SDA low, SCL low
            if (scl_rise) next_state = STOP_B;
        end
        STOP_B : begin
            // on SCL high drive SDA low → then release → STOP
            if (scl_rise) sda_drive_low = 1'b0;   // release for STOP
            if (scl_half_pulse) next_state = DONE;
        end
        //------------------------------------------------------------------
        DONE : begin
            if (!I2C_Start) next_state = IDLE;    // wait until start de-asserted
        end
        //------------------------------------------------------------------
        default : next_state = IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // sequential part
    // ----------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            bit_cnt      <= 3'd7;
            shift        <= '0;
            sending_addr <= 1'b0;
        end else begin
            state <= next_state;

            // ---------- load / shift bookkeeping -------------------
            // LOAD address right after START_B
            if (state == START_B && scl_fall) begin
                shift        <= {slave_addr, RW};
                bit_cnt      <= 3'd7;
                sending_addr <= 1'b1;
            end
            // SHIFT on every falling edge while sending bits
            else if (state == SEND_BYTE && scl_fall) begin
                shift   <= {shift[6:0], 1'b0};
                bit_cnt <= bit_cnt - 3'd1;
            end
            // after ACK of address byte
            else if (state == WAIT_ACK && sending_addr && scl_rise) begin
                sending_addr <= 1'b0;
                if (!RW) begin                       // prepare data byte for write
                    shift   <= data_in;
                    bit_cnt <= 3'd7;
                end
            end
            // shift IN while reading
            else if (state == READ_BYTE && scl_rise) begin
                shift   <= {shift[6:0], I2C_SDA};
                bit_cnt <= bit_cnt - 3'd1;
            end
        end
    end

    // ===============================================================
    // 3. Tri-state drive for SDA
    // ===============================================================
    assign I2C_SDA = sda_drive_low ? 1'b0 : 1'bz;  // open-drain behaviour

    // ===============================================================
    // 4. Outputs
    // ===============================================================
    assign data_out = shift;              // valid after DONE (for reads)
    assign busy     = (state != IDLE) && (state != DONE);
    assign I2C_En   = busy;               // identical meaning

endmodule