module I2C_driver(
    input  logic       clk,         // System clock
    input  logic       rst,         // Asynchronous reset
    input  logic       I2C_Start,   // Initiate a transaction when high
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read
    input  logic [9:0] slave_addr,  // 10-bit I2C slave address
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line (open-drain, master drives low, releases high)
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

    // --- Parameters ---
    parameter CLK_FREQ = 50_000_000; // 50 MHz system clock
    parameter SCL_FREQ = 100_000;   // 100 kHz I2C SCL clock
    // Calculate the count for half an SCL period.
    // For 100kHz SCL from 50MHz CLK: (50,000,000 / 100,000) / 2 = 500 / 2 = 250
    localparam SCL_HALF_PERIOD_COUNT = (CLK_FREQ / SCL_FREQ) / 2;

    // --- State Machine Definition ---
    typedef enum logic [4:0] {
        IDLE,              // Waiting for a new transaction request
        START_COND_1,      // SCL high, SDA high (pre-start setup)
        START_COND_2,      // SCL high, SDA low (actual start condition)
        ADDR_TX_BIT,       // Transmitting address/RW bit (SCL low, SDA set)
        ADDR_TX_CLK,       // Transmitting address/RW bit (SCL high, SDA stable)
        ACK_ADDR_RX_BIT,   // Receiving ACK for address (SCL low, SDA released)
        ACK_ADDR_RX_CLK,   // Receiving ACK for address (SCL high, SDA sampled)
        DATA_TX_BIT,       // Transmitting data bit (SCL low, SDA set)
        DATA_TX_CLK,       // Transmitting data bit (SCL high, SDA stable)
        ACK_DATA_RX_BIT,   // Receiving ACK for data (SCL low, SDA released)
        ACK_DATA_RX_CLK,   // Receiving ACK for data (SCL high, SDA sampled)
        DATA_RX_BIT,       // Receiving data bit (SCL low, SDA released)
        DATA_RX_CLK,       // Receiving data bit (SCL high, SDA sampled)
        ACK_TX_BIT,        // Transmitting ACK/NACK (SCL low, SDA set)
        ACK_TX_CLK,        // Transmitting ACK/NACK (SCL high, SDA stable)
        STOP_COND_1,       // SCL low, SDA low (pre-stop setup)
        STOP_COND_2,       // SCL high, SDA low (stop condition part 1)
        STOP_COND_3,       // SCL high, SDA high (actual stop condition)
        DONE_STATE         // Transaction complete, brief hold before IDLE
    } i2c_state_t;

    // --- Internal Signals ---
    i2c_state_t current_state, next_state;

    // SCL control signals (open-drain implementation)
    logic scl_out_reg;       // Value to drive SCL (always 0 when driving low)
    logic scl_oe_reg;        // Output enable for SCL (1 to drive, 0 to release)
    logic scl_internal_high; // Flag indicating I2C_SCL line is actually high (pulled up)
    logic [15:0] scl_clk_cnt; // Counter for SCL half-period timing
    logic scl_target_high;   // What the master *wants* SCL to be (high or low)
    logic scl_posedge_en;    // Pulse on SCL rising edge (after clock stretching)
    logic scl_negedge_en;    // Pulse on SCL falling edge

    // SDA control signals (bidirectional)
    logic sda_out_reg;       // Value to drive SDA (0 or 1)
    logic sda_oe_reg;        // Output enable for SDA (1 to drive, 0 to release)
    logic sda_in_reg;        // Registered value of I2C_SDA input

    // Data transfer registers
    logic [10:0] tx_addr_reg; // Holds 10-bit slave_addr + 1-bit R/W for transmission
    logic [7:0] tx_data_reg;  // Holds data_in for transmission
    logic [7:0] rx_data_reg;  // Accumulates received data
    logic [3:0] bit_counter;  // Counts bits for address (0-10) or data (0-7)

    // Control signals for module interface
    logic busy_reg;    // Internal busy status
    logic i2c_en_reg;  // Internal enable status
    logic start_pulse; // Edge detection for I2C_Start input

    // --- Output Assignments ---
    assign I2C_En = i2c_en_reg;
    assign busy = busy_reg;
    assign data_out = rx_data_reg;

    // I2C_SCL is open-drain: drive low (0) or release (1'bz)
    assign I2C_SCL = scl_oe_reg ? scl_out_reg : 1'bz;
    // I2C_SDA is bidirectional: drive low/high (0/1) or release (1'bz)
    assign I2C_SDA = sda_oe_reg ? sda_out_reg : 1'bz;

    // Register I2C_SDA input to avoid combinational loops and for stable sampling
    always_ff @(posedge clk) begin
        sda_in_reg <= I2C_SDA;
    end

    // --- SCL Clock Generator with Clock Stretching Support ---
    // This block generates the SCL clock and the synchronization pulses (posedge_en, negedge_en)
    // It also handles clock stretching by waiting for the actual I2C_SCL line to go high.
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            scl_clk_cnt <= 0;
            scl_target_high <= 1'b1; // Master wants SCL high initially
            scl_oe_reg <= 1'b0;      // Release SCL (pulled high externally)
            scl_out_reg <= 1'b0;     // Default drive low
            scl_posedge_en <= 1'b0;
            scl_negedge_en <= 1'b0;
            scl_internal_high <= 1'b1; // Assume SCL is high at reset
        end else begin
            scl_posedge_en <= 1'b0; // Clear pulses each clock cycle
            scl_negedge_en <= 1'b0;

            // Update scl_internal_high based on actual I2C_SCL line
            scl_internal_high <= I2C_SCL;

            
// Clock counter logic: increments every system clock cycle
            if (scl_clk_cnt == SCL_HALF_PERIOD_COUNT - 1) begin
                scl_clk_cnt <= 0;
                scl_target_high <= ~scl_target_high; // Toggle master's SCL target
            end else begin
                scl_clk_cnt <= scl_clk_cnt + 1;
            end

            // Control SCL output based on master's target and actual line state
            if (scl_target_high) begin // Master wants SCL high
                scl_oe_reg <= 1'b0; // Release SCL (allow pull-up to make it high)
                // Generate scl_posedge_en when SCL is actually high AND internal half-period elapsed
                if (scl_internal_high && (scl_clk_cnt == SCL_HALF_PERIOD_COUNT - 1)) begin
                    scl_posedge_en <= 1'b1;
                end
            end else begin // Master wants SCL low
                scl_oe_reg <= 1'b1; // Drive SCL
                scl_out_reg <= 1'b0; // Drive low
                // Generate scl_negedge_en when internal half-period elapsed (SCL is driven low)
                if (scl_clk_cnt == SCL_HALF_PERIOD_COUNT - 1) begin
                    scl_negedge_en <= 1'b1;
                end
            end
        end
    end

    // --- Start Pulse Generation ---
    // This logic ensures that a transaction is initiated only once per I2C_Start assertion.
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            start_pulse <= 1'b0;
        end else begin
            // Generate a pulse when I2C_Start is asserted and the module is not busy
            start_pulse <= I2C_Start && !busy_reg;
        end
    end

    // --- State Machine Logic ---
    // This block controls the I2C protocol sequence based on the current state and SCL edges.
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            busy_reg <= 1'b0;
            i2c_en_reg <= 1'b0;
            sda_oe_reg <= 1'b0;
            sda_out_reg <= 1'b1; // SDA high when idle (released, pulled up)
            bit_counter <= 0;
            tx_addr_reg <= 0;
            tx_data_reg <= 0;
            rx_data_reg <= 0;
        end else begin
            // Default assignments for signals that are not always driven in every state
            // These are active during a transaction and reset in IDLE/DONE_STATE
            busy_reg <= 1'b1;
            i2c_en_reg <= 1'b1;

            case (current_state)
                IDLE: begin
                    busy_reg <= 1'b0; // Not busy in IDLE
                    i2c_en_reg <= 1'b0; // Not enabled in IDLE
                    sda_oe_reg <= 1'b0; // SDA released (pulled high externally)
                    sda_out_reg <= 1'b1; // Ensure SDA is high if we were driving it
                    if (start_pulse) begin // Only start on a pulse from I2C_Start
                        next_state <= START_COND_1;
                        // Prepare address for transmission (10-bit address + 1-bit R/W)
                        tx_addr_reg[10:1] <= slave_addr; // MSB of slave_addr at tx_addr_reg[10]
                        tx_addr_reg[0] <= RW;            // R/W bit at tx_addr_reg[0]
                        bit_counter <= 10;               // Start count for 11 bits (10 down to 0)
                    end else begin
                        next_state <= IDLE;
                    end
                end

                START_COND_1: begin // SCL high, SDA high (pre-start setup)
                    sda_oe_reg <= 1'b1; // Master drives SDA
                    sda_out_reg <= 1'b1; // Drive SDA high
                    if (scl_posedge_en) begin // SCL just went high (or was high and half-period elapsed)
                        next_state <= START_COND_2;
                    end else begin
                        next_state <= START_COND_1;
                    end
                end

                START_COND_2: begin // SCL high, SDA low (actual start condition)
                    sda_oe_reg <= 1'b1;
                    sda_out_reg <= 1'b0; // Drive SDA low
                    if (scl_negedge_en) begin // SCL just went low, start address transmission
                        next_state <= ADDR_TX_BIT;
                    end else begin
                        next_state <= START_COND_2;
                    end
                end

                ADDR_TX_BIT: begin // SCL low, SDA set for address/RW bit
                    sda_oe_reg <= 1'b1;
                    sda_out_reg <= tx_addr_reg[bit_counter]; // Output current bit (MSB first)
                    if (scl_posedge_en) begin // SCL just went high, bit is stable
                        next_state <= ADDR_TX_CLK;
                    end else begin
                        next_state <= ADDR_TX_BIT;
                    end
                end

                ADDR_TX_CLK: begin // SCL high, SDA stable for address/RW bit
                    if (scl_negedge_en) begin // SCL just went low
                        if (bit_counter == 0) begin // All 11 bits (10 addr + 1 R/W) sent
                            next_state <= ACK_ADDR_RX_BIT; // Go to receive ACK
                        end else begin
                            bit_counter <= bit_counter - 1; // Move to next bit
                            next_state <= ADDR_TX_BIT;
                        end
                    end else begin
                        next_state <= ADDR_TX_CLK;
                    end
                end

                ACK_ADDR_RX_BIT: begin // SCL low, SDA released for ACK
                    sda_oe_reg <= 1'b0; // Release SDA for slave to drive ACK
                    if (scl_posedge_en) begin // SCL just went high, sample ACK
                        next_state <= ACK_ADDR_RX_CLK;
                    end else begin
                        next_state <= ACK_ADDR_RX_BIT;
                    end
                end

                ACK_ADDR_RX_CLK: begin // SCL high, SDA sampled for ACK
                    if (scl_negedge_en) begin // SCL just went low
                        if (sda_in_reg == 1'b1) begin // NACK received (SDA high)
                            // For simplicity, just stop on NACK. In a real design, might retry or signal error.
                            next_state <= STOP_COND_1;
                        end else begin // ACK received (SDA low)
                            if (RW == 1'b0) begin // Write transaction
                                bit_counter <= 7; // Prepare for 8 data bits (7 down to 0)
                                tx_data_reg <= data_in; // Load data to transmit
                                next_state <= DATA_TX_BIT;
                            end else begin // Read transaction
                                bit_counter <= 7; // Prepare for 8 data bits (7 down to 0)
                                next_state <= DATA_RX_BIT;
                            end
                        end
                    end else begin
                        next_state <= ACK_ADDR_RX_CLK;
                    end
                end

                DATA_TX_BIT: begin // SCL low, SDA set for data bit
                    sda_oe_reg <= 1'b1;
                    sda_out_reg <= tx_data_reg[bit_counter]; // Output current data bit (MSB first)
                    if (scl_posedge_en) begin
                        next_state <= DATA_TX_CLK;
                    end else begin
                        next_state <= DATA_TX_BIT;
                    end
                end

                DATA_TX_CLK: begin // SCL high, SDA stable for data bit
                    if (scl_negedge_en) begin
                        if (bit_counter == 0) begin // All 8 data bits sent
                            next_state <= ACK_DATA_RX_BIT; // Go to receive ACK
                        end else begin
                            bit_counter <= bit_counter - 1;
                            next_state <= DATA_TX_BIT;
                        end
                    end else begin
                        next_state <= DATA_TX_CLK;
                    end
                end

                ACK_DATA_RX_BIT: begin // SCL low, SDA released for ACK (after data write)
                    sda_oe_reg <= 1'b0; // Release SDA
                    if (scl_posedge_en) begin
                        next_state <= ACK_DATA_RX_CLK;
                    end else begin
                        next_state <= ACK_DATA_RX_BIT;
                    end
                end

                ACK_DATA_RX_CLK: begin // SCL high, SDA sampled for ACK (after data write)
                    if (scl_negedge_en) begin
                        if (sda_in_reg == 1'b1) begin // NACK received
                            // Handle NACK if needed, for now just proceed to stop
                        end
                        next_state <= STOP_COND_1; // After single byte write, go to STOP
                    end else begin
                        next_state <= ACK_DATA_RX_CLK;
                    end
                end

                DATA_RX_BIT: begin // SCL low, SDA released for data read
                    sda_oe_reg <= 1'b0; // Release SDA for slave to drive data
                    if (scl_posedge_en) begin
                        next_state <= DATA_RX_CLK;
                    end else begin
                        next_state <= DATA_RX_BIT;
                    end
                end

                DATA_RX_CLK: begin // SCL high, SDA sampled for data read
                    if (scl_negedge_en) begin
                        rx_data_reg[bit_counter] <= sda_in_reg; // Store received bit (MSB first)
                        if (bit_counter == 0) begin // All 8 data bits received
                            next_state <= ACK_TX_BIT; // Go to transmit ACK/NACK
                        end else begin
                            bit_counter <= bit_counter - 1;
                            next_state <= DATA_RX_BIT;
                        end
                    end else begin
                        next_state <= DATA_RX_CLK;
                    end
                end

                ACK_TX_BIT: begin // SCL low, SDA set for ACK/NACK (after data read)
                    sda_oe_reg <= 1'b1;
                    // For single byte read, send NACK (SDA high)
                    sda_out_reg <= 1'b1; // NACK
                    if (scl_posedge_en) begin
                        next_state <= ACK_TX_CLK;
                    end else begin
                        next_state <= ACK_TX_BIT;
                    end
                end

                ACK_TX_CLK: begin // SCL high, SDA stable for ACK/NACK (after data read)
                    if (scl_negedge_en) begin
                        next_state <= STOP_COND_1; // After single byte read, go to STOP
                    end else begin
                        next_state <= ACK_TX_CLK;
                    end
                end

                STOP_COND_1: begin // SCL low, SDA low (pre-stop setup)
                    sda_oe_reg <= 1'b1;
                    sda_out_reg <= 1'b0; // Drive SDA low
                    if (scl_posedge_en) begin // SCL just went high
                        next_state <= STOP_COND_2;
                    end else begin
                        next_state <= STOP_COND_1;
                    end
                end

                STOP_COND_2: begin // SCL high, SDA low (stop condition part 1)
                    sda_oe_reg <= 1'b1;
                    sda_out_reg <= 1'b0; // Keep SDA low
                    if (scl_posedge_en) begin // SCL is high, wait for next SCL half-period
                        next_state <= STOP_COND_3;
                    end else begin
                        next_state <= STOP_COND_2;
                    end
                end

                STOP_COND_3: begin // SCL high, SDA high (actual stop condition)
                    sda_oe_reg <= 1'b1;
                    sda_out_reg <= 1'b1; // Drive SDA high
                    if (scl_negedge_en) begin // SCL just went low, stop condition complete
                        next_state <= DONE_STATE;
                    end else begin
                        next_state <= STOP_COND_3;
                    end
                end

                DONE_STATE: begin
                    busy_reg <= 1'b0; // Transaction finished
                    i2c_en_reg <= 1'b0; // Module disabled
                    sda_oe_reg <= 1'b0; // Release SDA
                    sda_out_reg <= 1'b1; // Ensure SDA is high (pulled up)
                    next_state <= IDLE; // Return to idle
                end

                default: begin
                    next_state <= IDLE; // Should not happen, reset to IDLE
                end
            endcase
            current_state <= next_state;
        end
    end

endmodule