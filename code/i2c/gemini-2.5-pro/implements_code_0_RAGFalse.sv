/**
 * @brief I2C Master Controller
 * 
 * This module implements a single-byte I2C master controller. It supports 7-bit addressing
 * for both read and write operations.
 *
 * @param CLK_FREQ System clock frequency in Hz (e.g., 50_000_000 for 50MHz).
 * @param SCL_FREQ I2C SCL clock frequency in Hz (e.g., 100_000 for 100kHz).
 */
module I2C_driver #(
    parameter CLK_FREQ = 50_000_000, // System Clock Frequency: 50 MHz
    parameter SCL_FREQ = 100_000    // I2C Clock Frequency: 100 kHz
) (
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

    //--------------------------------------------------------------------------
    // Internal Parameters and State Definition
    //--------------------------------------------------------------------------
    localparam CLK_DIV_RATIO = CLK_FREQ / (SCL_FREQ * 4);

    typedef enum logic [3:0] {
        IDLE,
        START,
        TX_ADDR,
        WAIT_ACK1,
        TX_DATA,
        WAIT_ACK2,
        RX_DATA,
        SEND_NACK,
        STOP
    } fsm_state_t;

    //--------------------------------------------------------------------------
    // Internal Signals
    //--------------------------------------------------------------------------
    fsm_state_t state, next_state;

    // Clock generation signals
    logic [15:0] clk_div_cnt;
    logic        core_en;

    // FSM control signals
    logic [2:0] bit_cnt;
    logic [7:0] tx_buffer;
    logic [7:0] rx_buffer;
    logic       ack_in;

    // Latched transaction parameters
    logic [6:0] slave_addr_reg;
    logic       rw_reg;
    logic [7:0] data_in_reg;

    // Bidirectional SDA control
    logic sda_en;
    logic sda_out;

    //--------------------------------------------------------------------------
    // Clock Divider for FSM timing
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_cnt <= 0;
            core_en <= 1'b0;
        end else begin
            if (clk_div_cnt == CLK_DIV_RATIO - 1) begin
                clk_div_cnt <= 0;
                core_en <= I2C_En; // Only enable core tick during a transaction
            end else begin
                clk_div_cnt <= clk_div_cnt + 1;
                core_en <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Bidirectional SDA line driver
    //--------------------------------------------------------------------------
    assign I2C_SDA = sda_en ? sda_out : 1'bz;

    //--------------------------------------------------------------------------
    // FSM State Register
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    //--------------------------------------------------------------------------
    // FSM Combinational Logic
    //--------------------------------------------------------------------------
    always_comb begin
        // Default assignments to avoid latches
        next_state = state;
        I2C_En = 1'b1;
        busy = 1'b1;
        sda_en = 1'b0;
        sda_out = 1'b1;
        I2C_SCL = 1'b1;
        bit_cnt = bit_cnt; // Keep previous value unless changed
        tx_buffer = tx_buffer;
        data_out = rx_buffer;
        ack_in = I2C_SDA;

        case (state)
            IDLE: begin
                I2C_En = 1'b0;
                busy = 1'b0;
                I2C_SCL = 1'b1;
                sda_en = 1'b1; // Drive SDA high in idle
                sda_out = 1'b1;

                if (I2C_Start) begin
                    // Latch inputs and prepare for start condition
                    slave_addr_reg <= slave_addr;
                    rw_reg <= RW;
                    data_in_reg <= data_in;
                    tx_buffer <= {slave_addr, RW};
                    bit_cnt <= 7;
                    next_state = START;
                end else begin
                    next_state = IDLE;
                end
            end

            START: begin
                // Generate START condition: SDA goes low while SCL is high
                I2C_SCL = 1'b1;
                sda_en = 1'b1;
                sda_out = 1'b0;
                if (core_en) begin
                    next_state = TX_ADDR;
                end
            end

            TX_ADDR: begin
                // Transmit address byte, MSB first
                I2C_SCL = (clk_div_cnt < (CLK_DIV_RATIO / 2)); // SCL low for first half, high for second
                sda_en = 1'b1;
                sda_out = tx_buffer[bit_cnt];

                if (core_en && (clk_div_cnt > (CLK_DIV_RATIO * 3 / 4))) begin // Change state in last quarter
                    if (bit_cnt == 0) begin
                        bit_cnt <= 7; // Reset for next byte
                        next_state = WAIT_ACK1;
                    end else begin
                        bit_cnt <= bit_cnt - 1;
                    end
                end
            end

            WAIT_ACK1: begin
                // Release SDA and wait for slave ACK
                I2C_SCL = (clk_div_cnt < (CLK_DIV_RATIO / 2));
                sda_en = 1'b0; // Let slave drive SDA

                if (core_en && (clk_div_cnt > (CLK_DIV_RATIO * 3 / 4))) begin
                    if (ack_in == 1'b0) begin // ACK received
                        if (rw_reg) begin // Read operation
                            next_state = RX_DATA;
                        end else begin // Write operation
                            tx_buffer <= data_in_reg;
                            next_state = TX_DATA;
                        end
                    end else begin // NACK or error
                        next_state = STOP;
                    end
                end
            end

            TX_DATA: begin
                // Transmit data byte
                I2C_SCL = (clk_div_cnt < (CLK_DIV_RATIO / 2));
                sda_en = 1'b1;
                sda_out = tx_buffer[bit_cnt];

                if (core_en && (clk_div_cnt > (CLK_DIV_RATIO * 3 / 4))) begin
                    if (bit_cnt == 0) begin
                        next_state = WAIT_ACK2;
                    end else begin
                        bit_cnt <= bit_cnt - 1;
                    end
                end
            end

            WAIT_ACK2: begin
                // Release SDA and wait for slave ACK
                I2C_SCL = (clk_div_cnt < (CLK_DIV_RATIO / 2));
                sda_en = 1'b0;

                if (core_en && (clk_div_cnt > (CLK_DIV_RATIO * 3 / 4))) begin
                    // Regardless of ACK/NACK, proceed to STOP for single-byte write
                    next_state = STOP;
                end
            end

            RX_DATA: begin
                // Receive data byte
                I2C_SCL = (clk_div_cnt < (CLK_DIV_RATIO / 2));
                sda_en = 1'b0; // Let slave drive SDA

                if (core_en && (clk_div_cnt > (CLK_DIV_RATIO / 2))) begin // Sample when SCL is high
                    rx_buffer[bit_cnt] <= I2C_SDA;
                end

                if (core_en && (clk_div_cnt > (CLK_DIV_RATIO * 3 / 4))) begin
                    if (bit_cnt == 0) begin
                        next_state = SEND_NACK;
                    end else begin
                        bit_cnt <= bit_cnt - 1;
                    end
                end
            end

            SEND_NACK: begin
                // Send NACK to indicate end of read
                I2C_SCL = (clk_div_cnt < (CLK_DIV_RATIO / 2));
                sda_en = 1'b1;
                sda_out = 1'b1; // NACK is SDA high

                if (core_en && (clk_div_cnt > (CLK_DIV_RATIO * 3 / 4))) begin
                    next_state = STOP;
                end
            end

            STOP: begin
                // Generate STOP condition: SDA goes high while SCL is high
                I2C_SCL = 1'b1;
                sda_en = 1'b1;
                sda_out = 1'b0; // First, ensure SDA is low
                if (clk_div_cnt > (CLK_DIV_RATIO / 2)) begin
                    sda_out = 1'b1; // Then, SDA goes high
                end

                if (core_en) begin
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule