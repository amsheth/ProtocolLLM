// =============================================================================
// Simple single–byte I²C-MASTER,   7- or 10-bit addressing, R/W capable.
// – Generates START / Re-START / STOP
// – One data byte + ACK/NACK
// – Open-drain SCL & SDA
// – Busy flag and “transaction enable” flag
// =============================================================================
module I2C_driver #(
    // ------------------------------------------------------------
    // USER-MODIFIABLE PARAMETERS
    // ------------------------------------------------------------
    int unsigned SYS_CLK_FREQ = 50_000_000,   // Hz  : system-clock frequency
    int unsigned I2C_CLK_FREQ =   100_000     // Hz  : desired SCL
) (
    input  logic       clk,        // system clock
    input  logic       rst,        // asynchronous reset (active high)
    input  logic       I2C_Start,  // pulse ⇒ start a transaction
    input  logic       RW,         // 0 = write, 1 = read
    input  logic [9:0] slave_addr, // 10-bit address to be put on the bus
    input  logic [7:0] data_in,    // byte to write
    inout  tri         I2C_SDA,    // bidirectional open-drain
    output tri         I2C_SCL,    // open-drain clock
    output logic [7:0] data_out,   // byte read from slave
    output logic       I2C_En,     // high while module owns the bus
    output logic       busy        // same as I2C_En, one extra cycle early
);

    // ------------------------------------------------------------
    // 1.  Clock divider ( four phases / bit )
    // ------------------------------------------------------------
    localparam int DIVIDER = SYS_CLK_FREQ / (I2C_CLK_FREQ * 4);
    localparam int DIVW    = $clog2(DIVIDER);

    logic [DIVW-1:0] div_cnt;
    logic            scl_en_4x;       // enable @ 4×SCL (phases A,B,C,D)

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_cnt   <= '0;
            scl_en_4x <= 1'b0;
        end else if (div_cnt == DIVIDER-1) begin
            div_cnt   <= '0;
            scl_en_4x <= 1'b1;
        end else begin
            div_cnt   <= div_cnt + 1;
            scl_en_4x <= 1'b0;
        end
    end

    // ------------------------------------------------------------
    // 2.  Two open-drain output enables
    // ------------------------------------------------------------
    logic scl_drive_low;   // 1 = pull SCL low, 0 = release
    logic sda_drive_low;   // 1 = pull SDA low, 0 = release

    assign I2C_SCL = (scl_drive_low) ? 1'b0 : 1'bz;  // external PU resistor pulls high
    assign I2C_SDA = (sda_drive_low) ? 1'b0 : 1'bz;
    wire   sda_in  = I2C_SDA;                        // read back data

    // ------------------------------------------------------------
    // 3.  Main FSM
    // ------------------------------------------------------------
    // Each state lasts one 4×CLK phase (A,B,C,D = 00,01,10,11)
    typedef enum logic [4:0] {
        ST_IDLE,
        // START generation
        ST_START_A, ST_START_B,
        // 1st address byte (10-bit mode) or single 7-bit addr
        ST_ADDR,        ST_ADDR_ACK,
        ST_ADDR2,       ST_ADDR2_ACK,   // only if 10-bit
        // Data (write or read)
        ST_DATA,        ST_DATA_ACK,
        ST_READ_DATA,   ST_READ_ACK,
        // STOP
        ST_STOP_A,      ST_STOP_B,
        ST_DONE
    } state_t;

    state_t    state, n_state;
    logic [3:0] bit_cnt;              // counts down 7..0
    logic [7:0] shift_reg;            // holds byte being sent/received
    logic       ack_bit;              // stores ACK from slave

    // Handy short-cuts
    wire is10 = 1'b1;                 // instantiate as 10-bit master by default
    wire phase_B = scl_phase[1:0] == 2'd1;  // just after SCL transitions low→high
    wire phase_C = scl_phase[1:0] == 2'd2;  // SCL high
    wire phase_D = scl_phase[1:0] == 2'd3;  // just before SCL high→low

    // 4-phase tracker:  00 01 10 11 (A->B->C->D)
    logic [1:0] scl_phase;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) scl_phase <= 2'd0;
        else if (scl_en_4x) scl_phase <= scl_phase + 1'b1;
    end

    // ------------------------------------------------------------
    // 4.  Sequential part
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= ST_IDLE;
            bit_cnt       <= 4'd0;
            shift_reg     <= 8'd0;
            ack_bit       <= 1'b1;
            scl_drive_low <= 1'b1; // keep SCL low during reset
            sda_drive_low <= 1'b1; // keep SDA low during reset
            data_out      <= 8'd0;
        end
        else if (scl_en_4x) begin
            // ----------------------------------------------------
            // Combinational next-state logic has set n_state/…
            // Evaluate during *phase A* (scl_phase==00)
            // ----------------------------------------------------
            // Common default releases
            scl_drive_low <= 1'b0;           // release (let it go high)
            sda_drive_low <= 1'b0;

            case (state)
                // ------------------------------------------------
                ST_IDLE: begin
                    if (I2C_Start) begin
                        state         <= ST_START_A;
                        scl_drive_low <= 1'b1; // pull SCL low before START sequence
                    end
                end

                // ------------------------------------------------
                // START  = SDA high→low while SCL is 1
                //   A: SCL=1, SDA=1   (bus idle)
                //   B: SDA pulls low
                //   C: SCL pulls low -> enters data phase
                // ------------------------------------------------
                ST_START_A: begin
                    // ensure both released; bus should be idle
                    if (scl_phase == 2'd1) state <= ST_START_B;
                end
                ST_START_B: begin
                    sda_drive_low <= 1'b1;  // drive SDA low
                    if (scl_phase == 2'd2) state <= ST_ADDR; // SCL already high, next fall
                end

                // ------------------------------------------------
                // First address byte   (11110 AA9 AA8 R/W) for 10-bit
                // or 7-bit (AAA AAA R/W)
                // ------------------------------------------------
                ST_ADDR: begin
                    // Phase A: load shift register / counter (once)
                    if (scl_phase == 2'd0) begin
                        shift_reg <= is10 ? { 3'b111, 2'b10, slave_addr[9:8], RW }
                                          : { slave_addr[6:0], RW };
                        bit_cnt   <= 4'd7;
                    end
                    // Phase C: shift out next bit while SCL high
                    if (phase_C) begin
                        sda_drive_low <= ~shift_reg[7]; // drive 0 for '0', release for '1'
                    end
                    // Phase D: shift register ←<<1
                    if (phase_D) begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_cnt == 0) state <= ST_ADDR_ACK;
                        else bit_cnt <= bit_cnt - 1;
                    end
                end

                // ------------------------------------------------
                // ACK cycles: release SDA during bit time, sample at C-phase
                // ------------------------------------------------
                ST_ADDR_ACK, ST_ADDR2_ACK, ST_DATA_ACK, ST_READ_ACK: begin
                    // release SDA so slave can pull low
                    if (phase_C) ack_bit <= ~sda_in;  // ACK = SDA low
                    if (phase_D) begin
                        // decide next state
                        case (state)
                            ST_ADDR_ACK:   state <= is10 ? ST_ADDR2  : (RW ? ST_READ_DATA : ST_DATA);
                            ST_ADDR2_ACK:  state <= RW   ? ST_READ_DATA : ST_DATA;
                            ST_DATA_ACK:   state <= ST_STOP_A;
                            ST_READ_ACK:   state <= ST_STOP_A;
                        endcase
                    end
                end

                // ------------------------------------------------
                // SECOND address byte (lower 8 bits) – 10-bit only
                // ------------------------------------------------
                ST_ADDR2: begin
                    if (scl_phase == 2'd0) begin
                        shift_reg <= slave_addr[7:0];
                        bit_cnt   <= 4'd7;
                    end
                    if (phase_C) sda_drive_low <= ~shift_reg[7];
                    if (phase_D) begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_cnt == 0) state <= ST_ADDR2_ACK;
                        else bit_cnt <= bit_cnt - 1;
                    end
                end

                // ------------------------------------------------
                // WRITE DATA byte
                // ------------------------------------------------
                ST_DATA: begin
                    if (scl_phase == 2'd0) begin
                        shift_reg <= data_in;
                        bit_cnt   <= 4'd7;
                    end
                    if (phase_C) sda_drive_low <= ~shift_reg[7];
                    if (phase_D) begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_cnt == 0) state <= ST_DATA_ACK;
                        else bit_cnt <= bit_cnt - 1;
                    end
                end

                // ------------------------------------------------
                // READ DATA byte
                // ------------------------------------------------
                ST_READ_DATA: begin
                    if (scl_phase == 2'd0) begin
                        bit_cnt   <= 4'd7;
                        shift_reg <= '0;
                    end
                    // master releases SDA during data in
                    if (phase_C) begin
                        shift_reg <= { shift_reg[6:0], sda_in };
                    end
                    if (phase_D) begin
                        if (bit_cnt == 0) begin
                            data_out <= shift_reg;
                            state    <= ST_READ_ACK;
                        end
                        else bit_cnt <= bit_cnt - 1;
                    end
                end

                // ------------------------------------------------
                // STOP sequence:  SCL low, SDA low (A)
                //                 SCL high (B)
                //                 SDA high (C) – rising edge while SCL high
                // ------------------------------------------------
                ST_STOP_A: begin
                    scl_drive_low <= 1'b1;   // keep SCL low
                    sda_drive_low <= 1'b1;   // keep SDA low
                    if (phase_D) state <= ST_STOP_B;
                end
                ST_STOP_B: begin
                    scl_drive_low <= 1'b0;   // release SCL -> goes high
                    sda_drive_low <= 1'b1;   // still low
                    if (phase_C)   sda_drive_low <= 1'b0; // release SDA -> rises
                    if (phase_D)   state <= ST_DONE;
                end

                // ------------------------------------------------
                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------
    // 5.  Busy / enable indications
    // ------------------------------------------------------------
    assign I2C_En = (state != ST_IDLE);
    assign busy   = I2C_En;

endmodule