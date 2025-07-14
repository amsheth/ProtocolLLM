// -----------------------------------------------------------------------------
// Simple I²C single–byte master (7-bit address).
// System clock  : clk
// Generated SCL : ≈  (clk_freq)/(2*CLK_DIV)  (both high & low take CLK_DIV cycles)
//
// NOTE:
//   • Open-drain behaviour is modelled by tri–stating SDA when '1’ has to be put
//     on the bus.  An external pull-up is assumed (as in a real I²C bus).
//   • SCL is driven push–pull for simplicity; if open-drain is mandatory just
//     change the assignment exactly like SDA (drive ‘0’/Hi-Z).
//   • Only one data byte is transferred per transaction (easy to enlarge).
// -----------------------------------------------------------------------------
module I2C_driver
#(
    // When clk  = 25 MHz  and  CLK_DIV = 125  →  SCL ≈ 100 kHz
    // ( SCLfreq = clk / (2*CLK_DIV) )
    parameter int unsigned CLK_DIV = 125
)(
    input  logic        clk,          // System clock
    input  logic        rst,          // Asynchronous reset, active high

    input  logic        I2C_Start,    // Start a transaction
    input  logic        RW,           // 0 = write, 1 = read
    input  logic [6:0]  slave_addr,   // 7-bit slave address
    input  logic [7:0]  data_in,      // Byte to write

    inout  tri          I2C_SDA,      // I²C data (open-drain)
    output logic        I2C_SCL,      // I²C clock (see note above)

    output logic [7:0]  data_out,     // Byte read from the slave
    output logic        I2C_En,       // ‘1’ while state-machine is active
    output logic        busy          // Same as I2C_En (alias)
);

// -----------------------------------------------------------------------------
// Clock divider – produces “half-bit” enable tick (toggle SCL each tick)
// -----------------------------------------------------------------------------
logic [$clog2(CLK_DIV)-1:0] div_cnt;
logic                        scl_int, scl_en;   // Internal SCL & enable
logic                        tick;              // rising edge every CLK_DIV cycles

always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        div_cnt <= '0;
    end
    else if (scl_en) begin
        if (div_cnt == CLK_DIV-1)
            div_cnt <= '0;
        else
            div_cnt <= div_cnt + 1;
    end
    else
        div_cnt <= '0;
end

assign tick = (div_cnt == CLK_DIV-1);

// Toggle SCL every tick while enabled
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        scl_int <= 1'b1;          // Bus idle: SCL high
    else if (scl_en && tick)
        scl_int <= ~scl_int;
    else if (!scl_en)
        scl_int <= 1'b1;          // Release to idle high between transfers
end

assign I2C_SCL = scl_int;

// -----------------------------------------------------------------------------
// SDA open-drain handling
// -----------------------------------------------------------------------------
logic sda_out;  // value driven when OE asserted
logic sda_oe;   // 1 = drive sda_out (low), 0 = Hi-Z  (high through pull-up)

assign I2C_SDA = (sda_oe) ? sda_out : 1'bz;     // open-drain modelling
logic sda_in   = I2C_SDA;                       // read current bus level

// -----------------------------------------------------------------------------
// State-machine definitions
// -----------------------------------------------------------------------------
typedef enum logic [3:0] {
    IDLE,           // waiting for I2C_Start
    START,          // generate start condition
    SEND_ADDR,      // shift out 7b address + R/W
    ADDR_ACK,       // sample ACK after address
    WRITE_DATA,     // shift out data byte
    DATA_ACK,       // sample ACK after data
    READ_DATA,      // shift in data byte
    SEND_NACK,      // master puts NACK bit after last read byte
    STOP_1,         // SCL high while SDA low
    STOP_2          // raise SDA -> stop, then back to IDLE
} state_t;

state_t state, nxt_state;

logic [7:0] shift;          // shift register (tx or rx)
logic [2:0] bit_cnt;        // counts 7..0
logic       rw_reg;         // latched RW for current transfer
logic       addr_phase;     // ‘1’ while addressing
logic       capturing;      // ‘1’ while shifting data in

// Edge detectors for SCL to simplify timing decisions
logic scl_d;
always_ff @(posedge clk or posedge rst)
    if (rst) scl_d <= 1'b1;
    else     scl_d <= scl_int;

wire scl_rise = ( scl_d==0 && scl_int==1 );
wire scl_fall = ( scl_d==1 && scl_int==0 );

// -----------------------------------------------------------------------------
// Sequential part – state updates occur on *falling* edge of SCL (data launch)
// -----------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state      <= IDLE;
        sda_oe     <= 1'b1;
        sda_out    <= 1'b1;
        shift      <= 8'h00;
        bit_cnt    <= 3'd7;
        rw_reg     <= 1'b0;
        scl_en     <= 1'b0;
        data_out   <= 8'h00;
    end
    else begin
        // ---------------------------------------------------------------------
        // State transitions happen when we have a valid SCL falling edge
        // (i.e. we just finished the HIGH phase for a bit)
        // ---------------------------------------------------------------------
        if ( (state!=IDLE) && scl_fall ) begin
            case (state)
            // -------------------------------------------------- START
            START: begin
                // After SDA has been pulled low (while SCL high) we
                // now enable clocking and prepare to send address
                scl_en   <= 1'b1;                   // start toggling SCL
                state    <= SEND_ADDR;
                shift    <= {slave_addr, rw_reg};   // 7b + R/W
                bit_cnt  <= 3'd7;
                sda_oe   <= 1'b1;                   // drive SDA
                sda_out  <= {slave_addr, rw_reg}[7];// MSB
            end

            // -------------------------------------------------- ADDRESS BYTE
            SEND_ADDR: begin
                if (bit_cnt != 0) begin
                    bit_cnt <= bit_cnt - 1;
                    shift   <= {shift[6:0],1'b0};   // left shift (MSB first)
                    sda_out <= shift[6];            // next bit onto bus
                end
                else begin
                    // All bits sent, now release SDA for ACK
                    sda_oe  <= 1'b0;                // Hi-Z → slave can pull low
                    state   <= ADDR_ACK;
                end
            end

            // -------------------------------------------------- WRITE DATA
            WRITE_DATA: begin
                if (bit_cnt != 0) begin
                    bit_cnt <= bit_cnt - 1;
                    shift   <= {shift[6:0],1'b0};
                    sda_out <= shift[6];
                end
                else begin
                    sda_oe <= 1'b0;                // release for ACK
                    state  <= DATA_ACK;
                end
            end

            // -------------------------------------------------- READ DATA
            READ_DATA: begin
                if (bit_cnt != 0) begin
                    bit_cnt  <= bit_cnt - 1;
                end
                else begin
                    state    <= SEND_NACK;         // afterwards send NACK
                    sda_oe   <= 1'b1;
                    sda_out  <= 1'b1;              // NACK (logic ‘1’)
                end
            end

            // -------------------------------------------------- SEND_NACK finished
            SEND_NACK: begin
                state  <= STOP_1;
                scl_en <= 1'b0;                    // keep SCL high for STOP
            end

            // -------------------------------------------------- STOP first half
            STOP_1: begin
                // SCL already high, SDA still low
                sda_out <= 1'b1;                   // raise SDA while SCL high
                state   <= STOP_2;
            end

            // -------------------------------------------------- STOP second half
            STOP_2: begin
                // after one half SCL period we are done
                state   <= IDLE;
            end

            default: ; // do nothing for other states (ACK sampling etc.)
            endcase
        end // scl_fall (main sequencing)

        // ---------------------------------------------------------------------
        // Combinational-like actions that must happen on SCL rising edges
        // (e.g. sampling data or ACK from slave, capturing bits while reading)
        // ---------------------------------------------------------------------
        if (scl_rise) begin
            case (state)
            ADDR_ACK: begin
                // Sample ACK (expect 0); if NACK -> still finish transaction
                // After ACK field decide where to go
                if (rw_reg==1'b0) begin
                    // ------------- WRITE transaction
                    shift   <= data_in;
                    bit_cnt <= 3'd7;
                    sda_oe  <= 1'b1;
                    sda_out <= data_in[7];
                    state   <= WRITE_DATA;
                end
                else begin
                    // ------------- READ transaction
                    bit_cnt <= 3'd7;
                    sda_oe  <= 1'b0;   // keep Hi-Z to receive data
                    state   <= READ_DATA;
                end
            end

            DATA_ACK: begin
                // ACK after WRITE byte already sampled
                state  <= STOP_1;      // only single byte in this version
                scl_en <= 1'b0;        // keep SCL high ready for STOP
                sda_out<= 1'b0;        // ensure SDA low before raising later
                sda_oe <= 1'b1;
            end

            READ_DATA: begin
                // Shift in one data bit
                data_out[bit_cnt] <= sda_in;
            end
            endcase
        end // scl_rise
    end // !reset
end // always_ff

// -----------------------------------------------------------------------------
// IDLE state logic, asynchronous to simplify start detection
// -----------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state   <= IDLE;
        scl_en  <= 1'b0;
        sda_oe  <= 1'b1;
        sda_out <= 1'b1;
    end
    else if (state==IDLE) begin
        if (I2C_Start) begin
            // Latch direction for this transaction
            rw_reg   <= RW;
            // Prepare for Start condition ->
            sda_oe   <= 1'b1;           // drive SDA
            sda_out  <= 1'b1;           // ensure high
            scl_en   <= 1'b0;           // keep SCL high
            state    <= START;          // go generate START
            // SDA will be pulled LOW on first SCL fall (see START state)
        end
    end
end

// -----------------------------------------------------------------------------
// User flags
// -----------------------------------------------------------------------------
assign busy   = (state != IDLE);
assign I2C_En = busy;

endmodule