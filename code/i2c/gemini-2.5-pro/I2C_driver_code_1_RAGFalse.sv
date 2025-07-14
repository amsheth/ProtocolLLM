module I2C_driver(
    input  logic       clk,         // System clock
    input  logic       rst,         // Asynchronous reset
    input  logic       I2C_Start,   // Initiate a transaction when high
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [9:0] slave_addr,  // 10-bit I2C slave address
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    // SCL Frequency = System Clock / (2 * SCL_DIV_FACTOR)
    // Example: 50MHz clk, 100kHz SCL -> SCL_DIV_FACTOR = 50,000,000 / (2 * 100,000) = 250
    parameter SCL_DIV_FACTOR = 250;

    //--------------------------------------------------------------------------
    // State Machine Definition
    //--------------------------------------------------------------------------
    typedef enum logic [4:0] {
        ST_IDLE,
        ST_START_COND,
        ST_ADDR_1,
        ST_ADDR_1_ACK,
        ST_ADDR_2,
        ST_ADDR_2_ACK,
        ST_R_START,
        ST_ADDR_R,
        ST_ADDR_R_ACK,
        ST_WRITE_DATA,
        ST_WRITE_ACK,
        ST_READ_DATA,
        ST_READ_ACK,
        ST_STOP_COND
    } state_t;

    state_t state_reg, state_next;

    //--------------------------------------------------------------------------
    // Internal Signals and Registers
    //--------------------------------------------------------------------------
    // Clock generation
    logic       scl_clk_en;
    logic       scl_out_reg, scl_out_next;
    int         scl_cnt;

    // FSM control
    logic [3:0] bit_cnt_reg, bit_cnt_next;
    logic       ack_in;

    // Data registers
    logic [9:0] slave_addr_reg;
    logic       rw_reg;
    logic [7:0] data_w_reg;
    logic [7:0] data_r_reg, data_r_next;

    // SDA tri-state buffer control
    logic       sda_out_reg, sda_out_next;
    logic       sda_out_en_reg, sda_out_en_next;

    //--------------------------------------------------------------------------
    // Clock Divider for SCL
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scl_cnt <= 0;
            scl_clk_en <= 1'b0;
        end else begin
            scl_clk_en <= 1'b0;
            if (state_reg != ST_IDLE) begin
                if (scl_cnt == SCL_DIV_FACTOR - 1) begin
                    scl_cnt <= 0;
                    scl_clk_en <= 1'b1;
                end else begin
                    scl_cnt <= scl_cnt + 1;
                end
            end else begin
                scl_cnt <= 0; // Reset counter when idle
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sequential Logic (State and Data Registers)
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg      <= ST_IDLE;
            bit_cnt_reg    <= 0;
            scl_out_reg    <= 1'b1;
            sda_out_reg    <= 1'b1;
            sda_out_en_reg <= 1'b0;
            data_r_reg     <= 8'd0;
        end else begin
            if (scl_clk_en || (state_reg == ST_IDLE)) begin // State transitions on SCL edge or when starting
                state_reg      <= state_next;
                bit_cnt_reg    <= bit_cnt_next;
                scl_out_reg    <= scl_out_next;
                sda_out_reg    <= sda_out_next;
                sda_out_en_reg <= sda_out_en_next;
                data_r_reg     <= data_r_next;
            end
            // Latch inputs at the start of a transaction
            if (state_reg == ST_IDLE && I2C_Start) begin
                slave_addr_reg <= slave_addr;
                rw_reg         <= RW;
                data_w_reg     <= data_in;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Combinational Logic (FSM Next State and Output Logic)
    //--------------------------------------------------------------------------
    always_comb begin
        // Default assignments
        state_next      = state_reg;
        bit_cnt_next    = bit_cnt_reg;
        scl_out_next    = scl_out_reg;
        sda_out_next    = sda_out_reg;
        sda_out_en_next = sda_out_en_reg;
        data_r_next     = data_r_reg;
        ack_in          = I2C_SDA; // Read SDA line for ACK

        case (state_reg)
            ST_IDLE: begin
                scl_out_next    = 1'b1; // SCL is high when idle
                sda_out_next    = 1'b1; // SDA is high when idle
                sda_out_en_next = 1'b0; // Release the bus
                if (I2C_Start) begin
                    state_next = ST_START_COND;
                    bit_cnt_next = 0;
                end
            end

            ST_START_COND: begin
                // Generate START: SDA goes low while SCL is high
                sda_out_next    = 1'b0;
                sda_out_en_next = 1'b1;
                state_next      = ST_ADDR_1;
            end

            ST_ADDR_1: begin
                scl_out_next = ~scl_out_reg; // Toggle SCL
                if (scl_out_reg) begin // On falling edge of SCL
                    if (bit_cnt_reg == 8) begin
                        bit_cnt_next = 0;
                        state_next   = ST_ADDR_1_ACK;
                        sda_out_en_next = 1'b0; // Release SDA for ACK
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                    end
                end else begin // On rising edge of SCL
                    // Send 11110_A9_A8_0
                    case(bit_cnt_reg)
                        0: sda_out_next = 1'b1;
                        1: sda_out_next = 1'b1;
                        2: sda_out_next = 1'b1;
                        3: sda_out_next = 1'b1;
                        4: sda_out_next = 1'b0;
                        5: sda_out_next = slave_addr_reg[9];
                        6: sda_out_next = slave_addr_reg[8];
                        7: sda_out_next = 1'b0; // R/W bit = 0 for initial write
                    endcase
                end
            end

            ST_ADDR_1_ACK: begin
                scl_out_next = ~scl_out_reg;
                if (scl_out_reg) begin // On falling edge
                    if (ack_in) begin // NACK received
                        state_next = ST_STOP_COND;
                    end else begin // ACK received
                        if (rw_reg == 1'b0) begin // It's a WRITE operation
                            state_next = ST_ADDR_2;
                        end else begin // It's a READ operation
                            state_next = ST_R_START;
                        end
                        sda_out_en_next = 1'b1; // Re-enable SDA driver
                    end
                end
            end

            ST_ADDR_2: begin // Send lower 8 bits of address
                scl_out_next = ~scl_out_reg;
                if (scl_out_reg) begin // On falling edge
                    if (bit_cnt_reg == 8) begin
                        bit_cnt_next = 0;
                        state_next   = ST_ADDR_2_ACK;
                        sda_out_en_next = 1'b0; // Release SDA for ACK
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                    end
                end else begin // On rising edge
                    sda_out_next = slave_addr_reg[7 - bit_cnt_reg];
                end
            end

            ST_ADDR_2_ACK: begin
                scl_out_next = ~scl_out_reg;
                if (scl_out_reg) begin // On falling edge
                    if (ack_in) begin // NACK
                        state_next = ST_STOP_COND;
                    end else begin // ACK
                        state_next = ST_WRITE_DATA;
                        sda_out_en_next = 1'b1; // Re-enable SDA driver
                    end
                end
            end

            ST_R_START: begin // Repeated Start for Read
                scl_out_next = 1'b1;
                sda_out_next = 1'b0;
                state_next   = ST_ADDR_R;
            end

            ST_ADDR_R: begin // Send address with R/W=1
                scl_out_next = ~scl_out_reg;
                if (scl_out_reg) begin // On falling edge
                    if (bit_cnt_reg == 8) begin
                        bit_cnt_next = 0;
                        state_next   = ST_ADDR_R_ACK;
                        sda_out_en_next = 1'b0; // Release SDA for ACK
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                    end
                end else begin // On rising edge
                    // Send 11110_A9_A8_1
                    case(bit_cnt_reg)
                        0: sda_out_next = 1'b1;
                        1: sda_out_next = 1'b1;
                        2: sda_out_next = 1'b1;
                        3: sda_out_next = 1'b1;
                        4: sda_out_next = 1'b0;
                        5: sda_out_next = slave_addr_reg[9];
                        6: sda_out_next = slave_addr_reg[8];
                        7: sda_out_next = 1'b1; // R/W bit = 1 for read
                    endcase
                end
            end

            ST_ADDR_R_ACK: begin
                scl_out_next = ~scl_out_reg;
                if (scl_out_reg) begin // On falling edge
                    if (ack_in) begin // NACK
                        state_next = ST_STOP_COND;
                    end else begin // ACK
                        state_next = ST_READ_DATA;
                    end
                end
            end

            ST_WRITE_DATA: begin
                scl_out_next = ~scl_out_reg;
                if (scl_out_reg) begin // On falling edge
                    if (bit_cnt_reg == 8) begin
                        bit_cnt_next = 0;
                        state_next   = ST_WRITE_ACK;
                        sda_out_en_next = 1'b0; // Release SDA for ACK
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                    end
                end else begin // On rising edge
                    sda_out_next = data_w_reg[7 - bit_cnt_reg];
                end
            end

            ST_WRITE_ACK: begin
                scl_out_next = ~scl_out_reg;
                if (scl_out_reg) begin // On falling edge
                    // Transaction ends after data write, regardless of ACK
                    state_next = ST_STOP_COND;
                end
            end

            ST_READ_DATA: begin
                scl_out_next = ~scl_out_reg;
                if (scl_out_reg) begin // On falling edge
                    if (bit_cnt_reg == 8) begin
                        bit_cnt_next = 0;
                        state_next   = ST_READ_ACK;
                        sda_out_en_next = 1'b1; // Master drives ACK/NACK
                    end else begin
                        bit_cnt_next = bit_cnt_reg + 1;
                    end
                end else begin // On rising edge, sample data
                    data_r_next = {data_r_reg[6:0], ack_in};
                end
            end

            ST_READ_ACK: begin
                scl_out_next = ~scl_out_reg;
                // Send NACK (SDA=1) to signal end of read
                sda_out_next = 1'b1;
                if (scl_out_reg) begin // On falling edge
                    state_next = ST_STOP_COND;
                end
            end

            ST_STOP_COND: begin
                // Generate STOP: SDA goes high while SCL is high
                scl_out_next = 1'b1;
                sda_out_next = 1'b1;
                state_next   = ST_IDLE;
            end

            default: begin
                state_next = ST_IDLE;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // Output Assignments
    //--------------------------------------------------------------------------
    assign I2C_SCL  = scl_out_reg;
    assign busy     = (state_reg != ST_IDLE);
    assign I2C_En   = busy;
    assign data_out = data_r_reg;

    // Tri-state buffer for SDA line
    assign I2C_SDA = sda_out_en_reg ? sda_out_reg : 1'bz;

endmodule