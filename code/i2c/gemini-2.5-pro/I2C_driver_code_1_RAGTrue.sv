// I2C Master Controller with 10-bit Addressing Support
//
// Design Overview:
// 1. Clock Divider: Generates a core clock (core_clk_en) at 4x the SCL frequency
//    to create four distinct timing phases for each SCL cycle.
// 2. Phase Counter: A 2-bit counter (phase_cnt) cycles through the four phases
//    to control SCL and SDA signals at the bit level.
// 3. FSM: A high-level state machine manages the byte-level transaction sequence
//    (START, address, data, ACK, STOP).

module I2C_driver #(
    parameter CLK_FREQ   = 50_000_000, // System clock frequency in Hz
    parameter SCL_FREQ   = 100_000     // I2C SCL clock frequency in Hz
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       I2C_Start,
    input  logic       RW,          // 0 for write, 1 for read
    input  logic [9:0] slave_addr,
    input  logic [7:0] data_in,
    inout  logic       I2C_SDA,
    output logic       I2C_SCL,
    output logic [7:0] data_out,
    output logic       I2C_En,
    output logic       busy
);

    // Calculate the division ratio for the core clock
    localparam CORE_CLK_DIV = (CLK_FREQ / (SCL_FREQ * 4));

    // FSM state definitions
    typedef enum logic [4:0] {
        S_IDLE,
        S_START,
        S_TX_ADDR1,
        S_ACK1,
        S_TX_ADDR2,
        S_ACK2,
        S_REP_START,
        S_TX_ADDR_R,
        S_ACK_R,
        S_WRITE_DATA,
        S_ACK_W,
        S_READ_DATA,
        S_SEND_NACK,
        S_STOP,
        S_ERROR
    } state_t;

    state_t state, next_state;

    // Internal registers and signals
    logic [15:0] core_clk_cnt;
    logic        core_clk_en;
    logic [1:0]  phase_cnt;
    logic [3:0]  bit_cnt;

    logic        scl_reg;
    logic        sda_reg;
    logic        sda_en;
    logic [7:0]  data_shift;
    logic        ack_in;

    // Latched input registers
    logic        i_rw;
    logic [9:0]  i_slave_addr;
    logic [7:0]  i_data_in;

    //--------------------------------------------------------------------------
    // 1. Clock Generation Logic
    //--------------------------------------------------------------------------
    // Generate a core clock enable pulse at 4x SCL frequency
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            core_clk_cnt <= '0;
            core_clk_en  <= 1'b0;
        end else begin
            core_clk_en <= 1'b0;
            if (core_clk_cnt == CORE_CLK_DIV - 1) begin
                core_clk_cnt <= '0;
                core_clk_en  <= 1'b1;
            end else begin
                core_clk_cnt <= core_clk_cnt + 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // 2. Low-Level Bit Controller (Phase Counter)
    //--------------------------------------------------------------------------
    // This counter creates the four phases for each bit transfer
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            phase_cnt <= '0;
        end else if (core_clk_en) begin
            if (state == S_IDLE) begin
                phase_cnt <= '0;
            end else begin
                phase_cnt <= phase_cnt + 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // 3. High-Level FSM and Datapath Logic
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= S_IDLE;
            bit_cnt      <= '0;
            data_shift   <= '0;
            ack_in       <= 1'b1;
            i_rw         <= '0;
            i_slave_addr <= '0;
            i_data_in    <= '0;
        end else begin
            // Latch inputs at the beginning of a transaction
            if (I2C_Start && state == S_IDLE) begin
                i_rw         <= RW;
                i_slave_addr <= slave_addr;
                i_data_in    <= data_in;
            end

            if (core_clk_en) begin
                // FSM state transitions happen at the end of a bit cycle (phase 3)
                if (phase_cnt == 3) begin
                    state <= next_state;
                end

                // Update counters and shift registers based on the next state
                if (phase_cnt == 3) begin // End of bit cycle
                    case (next_state)
                        S_TX_ADDR1, S_TX_ADDR2, S_TX_ADDR_R, S_WRITE_DATA: begin
                            if (state != next_state) bit_cnt <= 4'd7; // Start of a new byte transfer
                            else bit_cnt <= bit_cnt - 1;
                            data_shift <= data_shift << 1;
                        end
                        S_READ_DATA: begin
                            if (state != next_state) bit_cnt <= 4'd7;
                            else bit_cnt <= bit_cnt - 1;
                            data_shift <= {data_shift[6:0], I2C_SDA}; // Shift in received bit
                        end
                        default: begin
                            bit_cnt <= '0;
                        end
                    endcase
                end
                
                // Latch ACK value from slave
                if (phase_cnt == 2) begin // Sample SDA when SCL is high
                    case (state)
                        S_ACK1, S_ACK2, S_ACK_R, S_ACK_W: begin
                            ack_in <= I2C_SDA;
                        end
                    endcase
                end
            end
        end
    end

    // FSM Combinational Logic (calculates next_state and control signals)
    always_comb begin
        next_state = state; // Default: stay in the same state

        // Default control signal values
        scl_reg  = 1'b1;
        sda_reg  = 1'b1;
        sda_en   = 1'b1;

        case (state)
            S_IDLE: begin
                scl_reg = 1'b1;
                sda_reg = 1'b1;
                sda_en  = 1'b1; // Drive SDA high in idle
                if (I2C_Start) begin
                    next_state = S_START;
                end
            end

            S_START: begin
                // START condition: SDA goes low while SCL is high
                scl_reg = 1'b1;
                sda_reg = (phase_cnt < 2) ? 1'b1 : 1'b0;
                if (phase_cnt == 3) begin
                    next_state = S_TX_ADDR1;
                    // Load first address byte: 11110 + Addr[9:8] + W(0)
                    data_shift = {5'b11110, i_slave_addr[9:8], 1'b0};
                end
            end

            S_TX_ADDR1, S_TX_ADDR2, S_TX_ADDR_R, S_WRITE_DATA: begin
                // Transmit one bit per 4 phases
                scl_reg = phase_cnt[1]; // SCL is high for phases 2 and 3
                sda_reg = data_shift[7];
                sda_en  = 1'b1;
                if (phase_cnt == 3 && bit_cnt == 0) begin
                    case(state)
                        S_TX_ADDR1:   next_state = S_ACK1;
                        S_TX_ADDR2:   next_state = S_ACK2;
                        S_TX_ADDR_R:  next_state = S_ACK_R;
                        S_WRITE_DATA: next_state = S_ACK_W;
                    endcase
                end
            end

            S_ACK1, S_ACK2, S_ACK_R, S_ACK_W: begin
                // Check for ACK from slave
                scl_reg = phase_cnt[1];
                sda_en  = 1'b0; // Release SDA for slave to drive
                if (phase_cnt == 3) begin
                    if (ack_in) begin // NACK received
                        next_state = S_ERROR;
                    end else begin // ACK received
                        case(state)
                            S_ACK1: begin
                                next_state = S_TX_ADDR2;
                                data_shift = i_slave_addr[7:0]; // Load lower 8 bits of address
                            end
                            S_ACK2: begin
                                if (i_rw) next_state = S_REP_START; // Go to read sequence
                                else begin
                                    next_state = S_WRITE_DATA; // Go to write data
                                    data_shift = i_data_in;
                                end
                            end
                            S_ACK_R:  next_state = S_READ_DATA;
                            S_ACK_W:  next_state = S_STOP; // End of write transaction
                        endcase
                    end
                end
            end

            S_REP_START: begin
                // Repeated START: SDA high, SCL high, then SDA low
                sda_reg = (phase_cnt < 1) ? 1'b1 : (phase_cnt < 3) ? 1'b1 : 1'b0;
                scl_reg = (phase_cnt < 2) ? 1'b0 : 1'b1;
                if (phase_cnt == 3) begin
                    next_state = S_TX_ADDR_R;
                    // Load address with Read bit: 11110 + Addr[9:8] + R(1)
                    data_shift = {5'b11110, i_slave_addr[9:8], 1'b1};
                end
            end

            S_READ_DATA: begin
                scl_reg = phase_cnt[1];
                sda_en  = 1'b0; // Release SDA for slave to send data
                if (phase_cnt == 3 && bit_cnt == 0) begin
                    next_state = S_SEND_NACK;
                end
            end

            S_SEND_NACK: begin
                // Master sends NACK to indicate end of read
                scl_reg = phase_cnt[1];
                sda_reg = 1'b1; // NACK bit
                sda_en  = 1'b1;
                if (phase_cnt == 3) begin
                    next_state = S_STOP;
                end
            end

            S_STOP: begin
                // STOP condition: SDA goes high while SCL is high
                scl_reg = (phase_cnt > 1);
                sda_reg = (phase_cnt < 2) ? 1'b0 : 1'b1;
                if (phase_cnt == 3) begin
                    next_state = S_IDLE;
                end
            end
            
            S_ERROR: begin
                // On NACK error, generate a STOP and go to IDLE
                scl_reg = (phase_cnt > 1);
                sda_reg = (phase_cnt < 2) ? 1'b0 : 1'b1;
                if (phase_cnt == 3) begin
                    next_state = S_IDLE;
                end
            end

        endcase
    end

    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    assign I2C_SCL = scl_reg;
    // Tristate buffer for the bidirectional SDA line
    assign I2C_SDA = sda_en ? sda_reg : 1'bz;

    assign busy     = (state != S_IDLE);
    assign I2C_En   = busy;
    // Output the received data just before the transaction ends
    assign data_out = (state == S_SEND_NACK) ? data_shift : '0;

endmodule