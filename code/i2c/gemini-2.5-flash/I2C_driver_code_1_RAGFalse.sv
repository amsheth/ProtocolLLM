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

    // --- Parameters ---
    // SCL_HALF_PERIOD_COUNT = (SYS_CLK_FREQ / (2 * I2C_SCL_FREQ)) - 1
    // Example: For SYS_CLK_FREQ = 50 MHz and I2C_SCL_FREQ = 100 kHz (Standard Mode)
    // SCL_HALF_PERIOD_COUNT = (50_000_000 / (2 * 100_000)) - 1 = 250 - 1 = 249
    parameter SCL_HALF_PERIOD_COUNT = 249; // *** ADJUST THIS VALUE FOR YOUR CLOCK FREQUENCIES ***

    // --- State Definitions ---
    typedef enum logic [4:0] {
        IDLE,           // Waiting for a new transaction
        START_COND_1,   // Generate Start: SDA high -> low while SCL high
        START_COND_2,   // Generate Start: SCL high -> low while SDA low
        ADDR_HIGH_TX,   // Transmit 7 MSBs of 10-bit address
        ADDR_HIGH_ACK,  // Wait for ACK after 7 MSBs
        ADDR_LOW_TX,    // Transmit 3 LSBs of 10-bit address + R/W bit
        ADDR_LOW_ACK,   // Wait for ACK after 3 LSBs + R/W bit
        DATA_TX,        // Transmit 8 bits of data
        DATA_TX_ACK,    // Wait for ACK after data transmission
        DATA_RX,        // Receive 8 bits of data
        DATA_RX_ACK,    // Master sends ACK/NACK after data reception
        STOP_COND_1,    // Generate Stop: SCL low -> high while SDA low
        STOP_COND_2     // Generate Stop: SDA low -> high while SCL high
    } i2c_state_t;

    i2c_state_t current_state, next_state;

    // --- Internal Signals ---
    logic [9:0] scl_clk_counter; // Counter for SCL clock division
    logic       scl_toggle;      // Flag to indicate SCL has just toggled
    logic       i2c_scl_reg;     // Internal SCL register (output to I2C_SCL)
    logic       i2c_sda_out;     // Data to drive onto I2C_SDA
    logic       i2c_sda_en;      // Enable for driving I2C_SDA (1: master drives, 0: master releases)
    logic [3:0] bit_counter;     // Counts bits for data/address transfer (0 to 7 for 8 bits)
    logic [9:0] addr_reg;        // Register to hold slave address for current transaction
    logic [7:0] data_tx_reg;     // Register to hold data to transmit for current transaction
    logic [7:0] data_rx_reg;     // Register to hold received data
    logic       rw_reg;          // Register to hold R/W bit for current transaction
    logic       start_req_reg;   // Latch for I2C_Start input

    // --- Output Assignments ---
    assign I2C_SCL  = i2c_scl_reg;
    assign I2C_SDA  = i2c_sda_en ? i2c_sda_out : 1'bz; // Bidirectional SDA control
    assign data_out = data_rx_reg;
    assign I2C_En   = (current_state != IDLE); // Active during transaction
    assign busy     = (current_state != IDLE);   // Busy during transaction

    // --- SCL Clock Generation ---
    // This block generates the I2C_SCL signal with a 50% duty cycle.
    // The SCL signal toggles when scl_clk_counter reaches SCL_HALF_PERIOD_COUNT.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scl_clk_counter <= 0;
            i2c_scl_reg     <= 1'b1; // SCL starts high (idle state)
            scl_toggle      <= 1'b0;
        end else begin
            if (current_state != IDLE) begin // Only generate SCL when busy
                if (scl_clk_counter == SCL_HALF_PERIOD_COUNT) begin
                    scl_clk_counter <= 0;
                    i2c_scl_reg     <= ~i2c_scl_reg; // Toggle SCL
                    scl_toggle      <= 1'b1;         // Indicate SCL has just toggled
                end else begin
                    scl_clk_counter <= scl_clk_counter + 1;
                    scl_toggle      <= 1'b0;
                end
            end else begin // In IDLE state, SCL is held high
                scl_clk_counter <= 0;
                i2c_scl_reg     <= 1'b1;
                scl_toggle      <= 1'b0;
            end
        end
    end

    // --- State Register ---
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // --- Input Registers (to sample inputs at start of transaction) ---
    // These registers hold the transaction parameters stable throughout the transaction.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            addr_reg      <= 10'b0;
            data_tx_reg   <= 8'b0;
            rw_reg        <= 1'b0;
            start_req_reg <= 1'b0;
        end else begin
            // Sample inputs only when a new transaction is requested and module is idle
            if (I2C_Start && !busy) begin
                addr_reg      <= slave_addr;
                data_tx_reg   <= data_in;
                rw_reg        <= RW;
                start_req_reg <= 1'b1; // Latch the start request
            end else if (busy && current_state == IDLE) begin // Clear start request once transaction is done
                start_req_reg <= 1'b0;
            end
        end
    end

    // --- Next State Logic and Output Control ---
    always_comb begin
        next_state   = current_state;
        i2c_sda_out  = 1'b1; // Default to high (released state for SDA)
        i2c_sda_en   = 1'b0; // Default to input (master releases SDA)
        // data_rx_reg retains its value unless explicitly updated in DATA_RX state

        case (current_state)
            IDLE: begin
                if (start_req_reg) begin // I2C_Start asserted and latched
                    next_state = START_COND_1;
                    // SCL is already high from idle state, SDA is high (released)
                end
            end

            START_COND_1: begin // Generate Start: SDA high -> low while SCL high
                i2c_sda_out = 1'b0; // Drive SDA low
                i2c_sda_en  = 1'b1; // Master drives SDA
                // Wait for SCL to be high and stable after SDA has fallen
                // Transition on the next SCL low edge
                if (scl_toggle && i2c_scl_reg == 1'b1) begin
                    next_state = START_COND_2;
                end
            end

            START_COND_2: begin // Generate Start: SCL high -> low while SDA low
                i2c_sda_out = 1'b0; // Keep SDA low
                i2c_sda_en  = 1'b1; // Master drives SDA
                if (scl_toggle && i2c_scl_reg == 1'b0) begin // SCL just went low
                    next_state  = ADDR_HIGH_TX;
                    bit_counter = 0; // Reset bit counter for address transmission
                end
            end

            ADDR_HIGH_TX: begin // Transmit 7 MSBs of 10-bit address (bits 9 to 3)
                i2c_sda_en = 1'b1; // Master drives SDA
                if (scl_toggle) begin
                    if (i2c_scl_reg == 1'b0) begin // SCL just went low, prepare next bit
                        i2c_sda_out = addr_reg[9 - bit_counter];
                    end else begin // SCL just went high, bit is stable
                        if (bit_counter == 6) begin // After 7 bits (0 to 6)
                            next_state = ADDR_HIGH_ACK;
                        end else begin
                            bit_counter = bit_counter + 1;
                        end
                    end
                end
            end

            ADDR_HIGH_ACK: begin // Wait for ACK from slave after 7 MSBs
                i2c_sda_en = 1'b0; // Master releases SDA (slave drives ACK/NACK)
                if (scl_toggle) begin
                    if (i2c_scl_reg == 1'b0) begin // SCL just went low, sample ACK
                        if (I2C_SDA == 1'b1) begin // NACK received
                            next_state = STOP_COND_1; // Go to stop on NACK
                        end else begin // ACK received
                            next_state = ADDR_LOW_TX;
                            bit_counter = 0; // Reset bit counter for next address part
                        end
                    end
                end
            end

            ADDR_LOW_TX: begin // Transmit 3 LSBs of 10-bit address (bits 2 to 0) + R/W bit
                i2c_sda_en = 1'b1; // Master drives SDA
                if (scl_toggle) begin
                    if (i2c_scl_reg == 1'b0) begin // SCL just went low, prepare next bit
                        if (bit_counter < 3) begin // Bits 2, 1, 0 of address
                            i2c_sda_out = addr_reg[2 - bit_counter];
                        end else begin // R/W bit (bit_counter == 3)
                            i2c_sda_out = rw_reg;
                        end
                    end else begin // SCL just went high, bit is stable
                        if (bit_counter == 3) begin // After 4 bits (0 to 3)
                            next_state = ADDR_LOW_ACK;
                        end else begin
                            bit_counter = bit_counter + 1;
                        end
                    end
                end
            end

            ADDR_LOW_ACK: begin // Wait for ACK from slave after 3 LSBs + R/W bit
                i2c_sda_en = 1'b0; // Master releases SDA
                if (scl_toggle) begin
                    if (i2c_scl_reg == 1'b0) begin // SCL just went low, sample ACK
                        if (I2C_SDA == 1'b1) begin // NACK received
                            next_state = STOP_COND_1; // Go to stop on NACK
                        end else begin // ACK received
                            if (rw_reg == 1'b0) begin // Write transaction
                                next_state = DATA_TX;
                                bit_counter = 0; // Reset bit counter for data
                            end else begin // Read transaction
                                next_state = DATA_RX;
                                bit_counter = 0; // Reset bit counter for data
                                data_rx_reg = 8'b0; // Clear data_out for new read
                            end
                        end
                    end
                end
            end

            DATA_TX: begin // Transmit 8 bits of data
                i2c_sda_en = 1'b1; // Master drives SDA
                if (scl_toggle) begin
                    if (i2c_scl_reg == 1'b0) begin // SCL just went low, prepare next bit
                        i2c_sda_out = data_tx_reg[7 - bit_counter];
                    end else begin // SCL just went high, bit is stable
                        if (bit_counter == 7) begin // After 8 bits (0 to 7)
                            next_state = DATA_TX_ACK;
                        end else begin
                            bit_counter = bit_counter + 1;
                        end
                    end
                end
            end

            DATA_TX_ACK: begin // Wait for ACK from slave after data transmission
                i2c_sda_en = 1'b0; // Master releases SDA
                if (scl_toggle) begin
                    if (i2c_scl_reg == 1'b0) begin // SCL just went low, sample ACK
                        // For simplicity, assume ACK and proceed to STOP.
                        // In a real design, NACK might trigger a retry or error.
                        next_state = STOP_COND_1;
                    end
                end
            end

            DATA_RX: begin // Receive 8 bits of data
                i2c_sda_en = 1'b0; // Master releases SDA (slave drives data)
                if (scl_toggle) begin
                    if (i2c_scl_reg == 1'b1) begin // SCL just went high, sample data
                        data_rx_reg[7 - bit_counter] = I2C_SDA;
                        if (bit_counter == 7) begin // After 8 bits (0 to 7)
                            next_state = DATA_RX_ACK;
                        end else begin
                            bit_counter = bit_counter + 1;
                        end
                    end
                end
            end

            DATA_RX_ACK: begin // Master sends ACK/NACK after data reception
                i2c_sda_en = 1'b1; // Master drives SDA
                // For a single byte read, send NACK (1'b1) to indicate end of read.
                // For multiple bytes, send ACK (1'b0) for all but the last byte.
                i2c_sda_out = 1'b1; // Send NACK (high) for single byte read
                if (scl_toggle) begin
                    if (i2c_scl_reg == 1'b0) begin // SCL just went low, ACK/NACK sent
                        next_state = STOP_COND_1;
                    end
                end
            end

            STOP_COND_1: begin // Generate Stop: SCL low -> high while SDA low
                i2c_sda_out = 1'b0; // Keep SDA low
                i2c_sda_en  = 1'b1; // Master drives SDA
                if (scl_toggle && i2c_scl_reg == 1'b1) begin // SCL just went high
                    next_state = STOP_COND_2;
                end
            end

            STOP_COND_2: begin // Generate Stop: SDA low -> high while SCL high
                i2c_sda_out = 1'b1; // Drive SDA high
                i2c_sda_en  = 1'b1; // Master drives SDA
                if (scl_toggle && i2c_scl_reg == 1'b1) begin // SCL is high, SDA just went high
                    next_state = IDLE; // Transaction complete
                end
            end

            default: begin
                next_state = IDLE; // Should not happen, return to IDLE
            end
        endcase
    end

endmodule