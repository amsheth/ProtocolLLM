// ===============================================================
// Simple single–byte I²C-MASTER (10-bit address) ― SystemVerilog
// ===============================================================
module I2C_driver
#(
    // -----------------------------------------------------------
    //  USER PARAMETERS ― change to suit your system
    // -----------------------------------------------------------
    parameter int SYS_CLK_FREQ = 50_000_000,      // Hz  (clk)
    parameter int I2C_FREQ     = 100_000          // Hz  (SCL)
)
(
    input  logic       clk,        // System clock
    input  logic       rst,        // Asynchronous active-high reset

    input  logic       I2C_Start,  // Rising-edge → start a new transaction
    input  logic       RW,         // 0 = write , 1 = read
    input  logic [9:0] slave_addr, // 10-bit slave address

    input  logic [7:0] data_in,    // Byte to write (when RW = 0)
    inout  tri         I2C_SDA,    // Bidirectional data (open-drain)
    output logic       I2C_SCL,    // I²C clock   (open-drain style)
    output logic [7:0] data_out,   // Byte read   (when RW = 1)

    output logic       I2C_En,     // Goes high during any bus activity
    output logic       busy        // Same as I2C_En (semantic sugar)
);

// -----------------------------------------------------------------------------
//  CLOCK DIVIDER : create 4 “quarter phases” per SCL period (low/rise/high/fall)
// -----------------------------------------------------------------------------
localparam int DIVIDER =   (SYS_CLK_FREQ / (I2C_FREQ * 4));  // integer
localparam int C_W     = $clog2(DIVIDER);

logic [C_W-1:0] div_cnt;
logic [1:0]     qphase;    // 0 = SCL low ; 1 = rising ; 2 = high ; 3 = falling
logic           scl_int;   // actual driven SCL (before tri-state)

// drive SCL according to phase
always_comb begin
    case (qphase)
        2'd1, 2'd2 : scl_int = 1'b1;   // rising / high
        default    : scl_int = 1'b0;   // low / falling
    endcase
end

// divider / phase generator
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        div_cnt <= '0;
        qphase  <= 2'd0;
    end else begin
        if (div_cnt == DIVIDER-1) begin
            div_cnt <= '0;
            qphase  <= qphase + 2'd1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end
end

// convenient strobes (one system-clock wide)
wire scl_posedge = (qphase == 2'd1) && (div_cnt == 0);  // start of HIGH
wire scl_negedge = (qphase == 2'd3) && (div_cnt == 0);  // start of LOW

// -----------------------------------------------------------------------------
//  OPEN-DRAIN SHAPING FOR SDA / SCL
// -----------------------------------------------------------------------------
logic sda_drive0;   // 1 → actively drive 0 , 0 → release (Z = logic-1 by pull-up)

assign I2C_SDA = (sda_drive0) ? 1'b0 : 1'bz;
assign I2C_SCL = (busy)       ? scl_int : 1'b1; // idle bus keeps SCL released high

// -----------------------------------------------------------------------------
//  BYTE SHIFTER & FSM
// -----------------------------------------------------------------------------
typedef enum logic [3:0] {
    ST_IDLE,
    ST_START,                // generate START
    ST_ADDR1, ST_ACK1,       // first address byte (11110xxR)
    ST_ADDR2, ST_ACK2,       // second address byte (addr[7:0])
    ST_WRITE, ST_WACK,       // single data byte write + slave ACK
    ST_READ,  ST_MACK,       // master reads byte + sends (N)ACK
    ST_STOP,                 // generate STOP
    ST_DONE
} state_t;

state_t state, n_state;

logic [7:0] shreg;           // shift register for TX/RX
logic [2:0] bit_cnt;         // counts 7→0
logic [7:0] rx_byte;
logic       ack_bit;

// -----------------------------------------------------------------------------
//  STATE MACHINE ― next state logic
// -----------------------------------------------------------------------------
always_comb begin
    n_state = state;
    unique case (state)
        ST_IDLE : begin
            if (I2C_Start) n_state = ST_START;
        end
        ST_START : begin
            if (scl_negedge) n_state = ST_ADDR1;
        end
        ST_ADDR1 : if (bit_cnt == 0 && scl_posedge) n_state = ST_ACK1;
        ST_ACK1  : if (scl_posedge) begin
                        n_state = ST_ADDR2;
                   end
        ST_ADDR2 : if (bit_cnt == 0 && scl_posedge) n_state = ST_ACK2;
        ST_ACK2  : if (scl_posedge) begin
                        n_state = (RW) ? ST_READ : ST_WRITE;
                   end
        // WRITE path ----------------------------------------------------------
        ST_WRITE : if (bit_cnt == 0 && scl_posedge) n_state = ST_WACK;
        ST_WACK  : if (scl_posedge) n_state = ST_STOP;
        // READ path -----------------------------------------------------------
        ST_READ  : if (bit_cnt == 0 && scl_posedge) n_state = ST_MACK;
        ST_MACK  : if (scl_posedge) n_state = ST_STOP;
        // END SEQUENCE --------------------------------------------------------
        ST_STOP  : if (scl_posedge) n_state = ST_DONE;
        ST_DONE  : if (scl_negedge) n_state = ST_IDLE;
        default  : n_state = ST_IDLE;
    endcase
end

// -----------------------------------------------------------------------------
//  SEQUENTIAL PART
// -----------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state      <= ST_IDLE;
        bit_cnt    <= 3'd7;
        shreg      <= 8'd0;
        rx_byte    <= 8'd0;
        sda_drive0 <= 1'b0;
    end else begin
        state <= n_state;

        // default : keep SDA released (logic-1) unless explicitly changed
        if (!busy) sda_drive0 <= 1'b0;

        // ---------------------------------------------------------------------
        //  STATE-SPECIFIC ACTIONS
        // ---------------------------------------------------------------------
        case (state)
            // ------------------------------------------------ START condition
            ST_START : begin
                // ensure SDA goes low while SCL is high (open-drain 0)
                sda_drive0 <= 1'b1;
            end

            // ---------------------------------------------- SEND FIRST BYTE
            ST_ADDR1 : begin
                if (state != n_state) begin
                    // load first address byte : 11110 A9 A8 R/W
                    shreg <= {3'b111, 2'b10, slave_addr[9:8], RW}; // 8 bits
                    bit_cnt <= 3'd7;
                end
                // shift out on falling edge (data must be valid before posedge)
                if (scl_negedge) begin
                    sda_drive0 <= ~shreg[7];  // drive 0 for bit ‘0’, else Hi-Z
                end
                if (scl_posedge) begin
                    shreg   <= {shreg[6:0],1'b0};
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end

            // --------------------------------------------- FIRST ACK (from slave)
            ST_ACK1 : begin
                sda_drive0 <= 1'b0;           // release SDA → slave drives ACK
                if (scl_posedge) ack_bit <= I2C_SDA;
            end

            // ---------------------------------------------- SEND SECOND BYTE
            ST_ADDR2 : begin
                if (state != n_state) begin
                    shreg   <= slave_addr[7:0];
                    bit_cnt <= 3'd7;
                end
                if (scl_negedge) sda_drive0 <= ~shreg[7];
                if (scl_posedge) begin
                    shreg   <= {shreg[6:0],1'b0};
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end

            // --------------------------------------------- SECOND ACK
            ST_ACK2 : begin
                sda_drive0 <= 1'b0;           // release for slave ACK
                if (scl_posedge) ack_bit <= I2C_SDA;
            end

            // ================================================= WRITE DATA BYTE
            ST_WRITE : begin
                if (state != n_state) begin
                    shreg   <= data_in;
                    bit_cnt <= 3'd7;
                end
                if (scl_negedge) sda_drive0 <= ~shreg[7];
                if (scl_posedge) begin
                    shreg   <= {shreg[6:0],1'b0};
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end
            ST_WACK : begin
                sda_drive0 <= 1'b0;           // release for slave ACK
                if (scl_posedge) ack_bit <= I2C_SDA;
            end

            // ================================================= READ DATA BYTE
            ST_READ : begin
                sda_drive0 <= 1'b0;           // release SDA (slave drives data)
                if (scl_posedge) begin
                    rx_byte <= {rx_byte[6:0], I2C_SDA};
                    bit_cnt <= bit_cnt - 1'b1;
                end
            end
            ST_MACK : begin
                // only single-byte read → master NACK (release high)
                sda_drive0 <= 1'b0;           // NACK = SDA high
            end

            // ------------------------------------------------ STOP condition
            ST_STOP : begin
                // first ensure SDA low while SCL low
                if (qphase == 2'd0) sda_drive0 <= 1'b1;
                // then release SDA while SCL high for STOP
                if (qphase == 2'd2) sda_drive0 <= 1'b0;
            end

            // ------------------------------------------------ DONE → back idle
            ST_DONE : begin
                if (qphase == 2'd3) begin      // after falling edge → IDLE
                    sda_drive0 <= 1'b0;
                end
            end
        endcase
    end
end

// capture byte for user during read
always_ff @(posedge clk) begin
    if (state == ST_MACK && scl_posedge)
        data_out <= rx_byte;
end

// ------------------------------------------------------------- STATUS / ENABLE
assign busy   = (state != ST_IDLE);
assign I2C_En = busy;

endmodule