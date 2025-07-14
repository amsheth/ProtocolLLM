module I2C_driver(
    input  logic       clk,         // System clock
    input  logic       rst,         // Asynchronous reset
    input  logic       I2C_Start,   // Initiate a transaction when high
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [6:0] slave_addr,  // 7-bit I2C slave address
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

    // Parameters for clock division
    parameter CLK_FREQ_HZ = 100_000_000; // Example: 100 MHz system clock
    parameter I2C_FREQ_HZ = 100_000;    // Example: 100 kHz I2C SCL frequency
    parameter SCL_HALF_PERIOD_CYCLES = (CLK_FREQ_HZ / I2C_FREQ_HZ) / 2;
    localparam SCL_COUNTER_WIDTH = $clog2(SCL_HALF_PERIOD_CYCLES);

    // Internal SCL clock generation signals
    logic [SCL_COUNTER_WIDTH-1:0] scl_clk_cnt;
    logic scl_i;        // Internal SCL state (0: low, 1: high)
    logic scl_cnt_done; // Flag indicating end of a half SCL period

    // SDA control signals
    logic sda_out_val; // Value to drive on SDA
    logic sda_out_en;  // Enable for SDA output (1 to drive, 0 to release)
    logic sda_in_val;  // Value read from SDA bus

    // State machine registers
    typedef enum logic [4:0] {
        IDLE,
        START_COND_1, START_COND_2,
        ADDR_WRITE_TX, ADDR_WRITE_ACK,
        DATA_WRITE_TX, DATA_WRITE_ACK,
        REPEATED_START_COND_1, REPEATED_START_COND_2,
        ADDR_READ_TX, ADDR_READ_ACK,
        DATA_READ_RX, DATA_READ_NACK,
        STOP_COND_1, STOP_COND_2
    } i2c_state_e;

    i2c_state_e current_state, next_state;

    // Data and bit counters
    logic [7:0] tx_byte_reg; // Byte currently being transmitted
    logic [7:0] rx_byte_reg; // Byte currently being received
    logic [3:0] bit_counter; // Counts 0 to 8 for 9 bits (8 data + 1 ACK/NACK)

    // Registers to store inputs at the start of a transaction
    logic [6:0] stored_slave_addr;
    logic       stored_rw;
    logic [7:0] stored_data_in;

    // Output assignments
    assign busy = (current_state != IDLE);
    assign I2C_En = busy;
    assign data_out = rx_byte_reg;

    // I2C_SCL output driver (master drives low, releases high)
    assign I2C_SCL = (scl_i == 1'b0) ? 1'b0 : 1'bz;

    // I2C_SDA output driver (master drives or releases)
    assign I2C_SDA = sda_out_en ? sda_out_val : 1'bz;

    // Read actual SDA bus value
    assign sda_in_val = I2C_SDA;

    // Clock divider for SCL
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scl_clk_cnt <= '0;
            scl_i <= 1'b1; // SCL starts high (released)
            scl_cnt_done <= 1'b0;
        end else begin
            scl_cnt_done <= 1'b0;
            if (scl_clk_cnt == SCL_HALF_PERIOD_CYCLES - 1) begin
                scl_clk_cnt <= '0;
                scl_i <= ~scl_i; // Toggle internal SCL state
                scl_cnt_done <= 1'b1; // Indicate half-period is done
            end else begin
                scl_clk_cnt <= scl_clk_cnt + 1;
            end
        end
    end

    // Store input parameters when a transaction starts
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            stored_slave_addr <= '0;
            stored_rw <= '0;
            stored_data_in <= '0;
        end else if (I2C_Start && current_state == IDLE) begin
            stored_slave_addr <= slave_addr;
            stored_rw <= RW;
            stored_data_in <= data_in;
        end
    end

    // State machine sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            tx_byte_reg <= '0;
            rx_byte_reg <= '0;
            bit_counter <= '0;
            // Initial SDA state: released (high due to pull-up)
            sda_out_val <= 1'b1;
            sda_out_en <= 1'b0;
        end else begin
            current_state <= next_state;
            // Default SDA to released unless explicitly driven in combinational logic
            sda_out_en <= 1'b0;
            sda_out_val <= 1'b1; // Default to high when released
        end
    end

    // State machine combinational logic
    always_comb begin
        next_state = current_state;
        // Default values for outputs driven by FSM
        sda_out_val = 1'b1; // Default SDA to high
        sda_out_en = 1'b0;   // Default SDA to released

        case (current_state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START_COND_1;
                end
            end

            START_COND_1: begin // SCL high, SDA high -> SDA low
                // SCL is high (scl_i = 1). Drive SDA low.
                sda_out_val = 1'b0;
                sda_out_en = 1'b1;
                if (scl_cnt_done && scl_i == 1'b0) begin // SCL just went low
                    next_state = ADDR_WRITE_TX;
                    bit_counter = 0;
                    tx_byte_reg = {stored_slave_addr, 1'b0}; // First byte: Address + Write bit
                end
            end

            ADDR_WRITE_TX: begin // Transmit 8 bits of address + R/W
                // SCL is low (scl_i = 0). Drive SDA with current bit.
                sda_out_val = tx_byte_reg[7 - bit_counter];
                sda_out_en = 1'b1;

                if (scl_cnt_done) begin // SCL just went high
                    if (I2C_SCL == 1'b1) begin // Wait for actual SCL to be high (clock stretching)
                        if (bit_counter == 7) begin // Last bit sent
                            next_state = ADDR_WRITE_ACK;
                        end else begin
                            bit_counter = bit_counter + 1;
                        end
                    end
                end
            end

            ADDR_WRITE_ACK: begin // Check ACK after address write
                // SCL is low (scl_i = 0). Release SDA for slave ACK.
                sda_out_en = 1'b0;

                if (scl_cnt_done) begin // SCL just went high
                    if (I2C_SCL == 1'b1) begin // Wait for actual SCL to be high
                        if (sda_in_val == 1'b0) begin // ACK received
                            if (stored_rw == 1'b0) begin // Write transaction: next send data_in
                                tx_byte_reg = stored_data_in;
                                next_state = DATA_WRITE_TX;
                                bit_counter = 0;
                            end else begin // Read transaction: next send memory address (data_in)
                                tx_byte_reg = stored_data_in; // data_in is memory address for read
                                next_state = DATA_WRITE_TX;
                                bit_counter = 0;
                            end
                        end else begin // NACK received
                            next_state = STOP_COND_1; // NACK means end of transfer or error
                        end
                    end
                end
            end

            DATA_WRITE_TX: begin // Transmit 8 bits of data (or memory address)
                // SCL is low (scl_i = 0). Drive SDA with current bit.
                sda_out_val = tx_byte_reg[7 - bit_counter];
                sda_out_en = 1'b1;

                if (scl_cnt_done) begin // SCL just went high
                    if (I2C_SCL == 1'b1) begin // Wait for actual SCL to be high
                        if (bit_counter == 7) begin // Last bit sent
                            next_state = DATA_WRITE_ACK;
                        end else begin
                            bit_counter = bit_counter + 1;
                        end
                    end
                end
            end

            DATA_WRITE_ACK: begin // Check ACK after data write (or memory address write)
                // SCL is low (scl_i = 0). Release SDA for slave ACK.
                sda_out_en = 1'b0;

                if (scl_cnt_done) begin // SCL just went high
                    if (I2C_SCL == 1'b1) begin // Wait for actual SCL to be high
                        if (sda_in_val == 1'b0) begin // ACK received
                            if (stored_rw == 1'b0) begin // Write transaction: single byte write done
                                next_state = STOP_COND_1;
                            end else begin // Read transaction: memory address sent, now repeated start
                                next_state = REPEATED_START_COND_1;
                            end
                        end else begin // NACK received
                            next_state = STOP_COND_1; // NACK means end of transfer or error
                        end
                    end
                end
            end

            REPEATED_START_COND_1: begin // Prepare for Repeated Start (SCL low -> high)
                // From previous ACK, SCL is low, SDA is low.
                // Release SDA to allow it to be pulled high.
                sda_out_en = 1'b0;
                if (scl_cnt_done && I2C_SCL == 1'b1) begin // SCL just went high and is high
                    next_state = REPEATED_START_COND_2;
                end
            end

            REPEATED_START_COND_2: begin // Generate Repeated Start (SDA high -> low while SCL high)
                // SCL is high. Drive SDA low.
                sda_out_val = 1'b0;
                sda_out_en = 1'b1;
                if (scl_cnt_done && scl_i == 1'b0) begin // SCL just went low
                    next_state = ADDR_READ_TX;
                    bit_counter = 0;
                    tx_byte_reg = {stored_slave_addr, 1'b1}; // Next byte: Address + Read bit
                end
            end

            ADDR_READ_TX: begin // Transmit 8 bits of address + read bit
                // SCL is low (scl_i = 0). Drive SDA with current bit.
                sda_out_val = tx_byte_reg[7 - bit_counter];
                sda_out_en = 1'b1;

                if (scl_cnt_done) begin // SCL just went high
                    if (I2C_SCL == 1'b1) begin // Wait for actual SCL to be high
                        if (bit_counter == 7) begin // Last bit sent
                            next_state = ADDR_READ_ACK;
                        end else begin
                            bit_counter = bit_counter + 1;
                        end
                    end
                end
            end

            ADDR_READ_ACK: begin // Check ACK after address read
                // SCL is low (scl_i = 0). Release SDA for slave ACK.
                sda_out_en = 1'b0;

                if (scl_cnt_done) begin // SCL just went high
                    if (I2C_SCL == 1'b1) begin // Wait for actual SCL to be high
                        if (sda_in_val == 1'b0) begin // ACK received
                            next_state = DATA_READ_RX;
                            bit_counter = 0; // Reset for data read
                            rx_byte_reg = '0; // Clear previous received data
                        end else begin // NACK received
                            next_state = STOP_COND_1; // NACK means end of transfer or error
                        end
                    end
                end
            end

            DATA_READ_RX: begin // Receive 8 bits of data
                // SCL is low (scl_i = 0). Release SDA for slave to drive data.
                sda_out_en = 1'b0;

                if (scl_cnt_done) begin // SCL just went high
                    if (I2C_SCL == 1'b1) begin // Wait for actual SCL to be high
                        rx_byte_reg[7 - bit_counter] = sda_in_val; // Capture data bit
                        if (bit_counter == 7) begin // Last bit read
                            next_state = DATA_READ_NACK; // Send NACK after last byte read
                        end else begin
                            bit_counter = bit_counter + 1;
                        end
                    end
                end
            end

            DATA_READ_NACK: begin // Send NACK after reading
                // SCL is low (scl_i = 0). Drive SDA high for NACK.
                sda_out_val = 1'b1;
                sda_out_en = 1'b1;

                if (scl_cnt_done) begin // SCL just went high
                    if (I2C_SCL == 1'b1) begin // Wait for actual SCL to be high
                        next_state = STOP_COND_1;
                    end
                end
            end

            STOP_COND_1: begin // Prepare for Stop (SDA low while SCL low -> SCL high)
                // SCL is low (scl_i = 0). Ensure SDA is low.
                sda_out_val = 1'b0;
                sda_out_en = 1'b1;
                if (scl_cnt_done && I2C_SCL == 1'b1) begin // SCL just went high and is high
                    next_state = STOP_COND_2;
                end
            end

            STOP_COND_2: begin // Generate Stop (SDA low -> high while SCL high)
                // SCL is high. Drive SDA high.
                sda_out_val = 1'b1;
                sda_out_en = 1'b1;
                if (scl_cnt_done && scl_i == 1'b0) begin // SCL just went low
                    next_state = IDLE; // Transaction complete
                end
            end

            default: next_state = IDLE; // Should not happen
        endcase
    end

endmodule