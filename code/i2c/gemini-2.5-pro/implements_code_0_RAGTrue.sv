/**
 * @brief I2C Master Controller
 *
 * This module implements a single-master I2C controller capable of performing
 * single-byte read and write transactions.
 *
 * @param SYS_CLK_FREQ System clock frequency in Hz (e.g., 50MHz)
 * @param SCL_FREQ     Desired I2C SCL clock frequency in Hz (e.g., 100kHz)
 */
module I2C_driver #(
    parameter SYS_CLK_FREQ = 50_000_000, // 50 MHz System Clock
    parameter SCL_FREQ     = 100_000    // 100 kHz I2C Clock
) (
    // System Interface
    input  logic       clk,
    input  logic       rst,

    // User Command Interface
    input  logic       I2C_Start,
    input  logic       RW,          // 0 for Write, 1 for Read
    input  logic [6:0] slave_addr,
    input  logic [7:0] data_in,

    // I2C Bus Interface
    inout  logic       I2C_SDA,
    output logic       I2C_SCL,

    // Status and Data Output
    output logic [7:0] data_out,
    output logic       I2C_En,
    output logic       busy
);

    // Calculate the division factor for the SCL clock generator.
    // We create a tick at 4x the SCL frequency to control the 4 phases of the SCL signal.
    localparam CLK_DIV_COUNT = (SYS_CLK_FREQ / (SCL_FREQ * 4));

    // FSM state definitions
    typedef enum logic [3:0] {
        IDLE,
        START,
        WRITE_BYTE,
        READ_BYTE,
        GET_ACK,
        SEND_NACK,
        STOP
    } fsm_state_t;

    // Internal Registers
    fsm_state_t state, next_state;

    // Clock generation signals
    logic [15:0] clk_div_counter;
    logic        scl_tick;

    // State machine control signals
    logic [1:0]  phase_ctr;      // Controls 4 phases of SCL clock
    logic [2:0]  bit_counter;    // Counts bits within a byte transfer
    logic        ack_in;         // Stores the received ACK bit
    logic        sent_addr_flag; // Flag to distinguish address ACK from data ACK

    // Latched command and data registers
    logic [7:0]  tx_buffer;      // Buffer for data to be transmitted (addr+rw, data)
    logic [7:0]  rx_buffer;      // Buffer for received data
    logic        cmd_reg;        // Latched RW command
    logic [6:0]  addr_reg;       // Latched slave address
    logic [7:0]  data_w_reg;     // Latched write data

    // I2C line control
    logic        scl_out;
    logic        sda_out;
    logic        sda_en;

    // --- 1. Clock Generation ---
    // Generates a periodic tick (scl_tick) at 4x the SCL frequency.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_counter <= 0;
            scl_tick <= 0;
        end else begin
            if (clk_div_counter >= CLK_DIV_COUNT - 1) begin
                clk_div_counter <= 0;
                scl_tick <= 1;
            end else begin
                clk_div_counter <= clk_div_counter + 1;
                scl_tick <= 0;
            end
        end
    end

    // --- 2. State Machine Sequential Logic ---
    // This block handles state transitions and updates registers on each scl_tick.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            phase_ctr <= 0;
            bit_counter <= 7;
            sent_addr_flag <= 0;
            // Initialize other registers on reset
            tx_buffer <= 0;
            rx_buffer <= 0;
            cmd_reg <= 0;
            addr_reg <= 0;
            data_w_reg <= 0;
        end else begin
            if (scl_tick) begin
                state <= next_state;
                // Latch inputs only when starting a new transaction from IDLE
                if (state == IDLE && next_state != IDLE) begin
                    cmd_reg <= RW;
                    addr_reg <= slave_addr;
                    data_w_reg <= data_in;
                    tx_buffer <= {slave_addr, RW};
                    sent_addr_flag <= 1; // We are about to send the address
                    bit_counter <= 7;
                end

                // Update counters and buffers based on the current state
                if (state == WRITE_BYTE || state == READ_BYTE) begin
                    if (phase_ctr == 3) begin // End of an SCL cycle
                        bit_counter <= bit_counter - 1;
                    end
                end

                if (state == READ_BYTE && phase_ctr == 2) begin // SCL is high
                    rx_buffer[bit_counter] <= I2C_SDA;
                end

                // Reset bit counter when moving to a new byte operation
                if ((state == GET_ACK && next_state == WRITE_BYTE) || (state == STOP && next_state == IDLE)) begin
                    bit_counter <= 7;
                end

                // Clear the address flag after it has been processed in GET_ACK
                if (state == GET_ACK) begin
                    sent_addr_flag <= 0;
                end

                // Advance the 4-phase SCL clock counter
                if (state != IDLE) begin
                    phase_ctr <= phase_ctr + 1;
                end else begin
                    phase_ctr <= 0;
                
end
            end
        end
    end

    // --- 3. State Machine Combinational Logic ---
    // This block determines the next state and control signal values based on the current state.
    always_comb begin
        next_state = state;
        scl_out = 1'b1;
        sda_out = 1'b1;
        sda_en = 1'b0; // Default to high-impedance (reading)
        ack_in = I2C_SDA;

        case (state)
            IDLE: begin
                scl_out = 1'b1;
                sda_en = 1'b0; // Release the bus
                if (I2C_Start) begin
                    next_state = START;
                end
            end

            START: begin
                // START condition: SDA goes low while SCL is high
                case (phase_ctr)
                    0: begin scl_out = 1'b1; sda_out = 1'b1; sda_en = 1'b1; end
                    1: begin scl_out = 1'b1; sda_out = 1'b0; sda_en = 1'b1; end
                    2: begin scl_out = 1'b0; sda_out = 1'b0; sda_en = 1'b1; end
                    default: next_state = WRITE_BYTE;
                endcase
            end

            WRITE_BYTE: begin
                // Transmit one bit per SCL cycle
                sda_out = tx_buffer[bit_counter];
                sda_en = 1'b1;
                case (phase_ctr)
                    0, 1: scl_out = 1'b0; // Data changes when SCL is low
                    2, 3: scl_out = 1'b1; // Data stable when SCL is high
                endcase
                if (bit_counter == 0 && phase_ctr == 3) begin
                    next_state = GET_ACK;
                end
            end

            GET_ACK: begin
                // Release SDA and pulse SCL to read the ACK bit
                sda_en = 1'b0;
                case (phase_ctr)
                    0, 1: scl_out = 1'b0;
                    2:    scl_out = 1'b1; // Slave drives SDA low for ACK
                    3: begin
                        scl_out = 1'b0;
                        if (ack_in == 1'b0) begin // ACK received
                            if (sent_addr_flag) begin
                                if (cmd_reg == 1'b1) begin // It was a READ command
                                    next_state = READ_BYTE;
                                end else begin // It was a WRITE command
                                    tx_buffer = data_w_reg; // Load data to transmit
                                    next_state = WRITE_BYTE;
                                end
                            end else begin // Data ACK received, transaction done
                                next_state = STOP;
                            end
                        end else begin // NACK received, terminate
                            next_state = STOP;
                        end
                    end
                endcase
            end

            READ_BYTE: begin
                // Release SDA and generate SCL pulses to receive data
                sda_en = 1'b0;
                case (phase_ctr)
                    0, 1: scl_out = 1'b0;
                    2, 3: scl_out = 1'b1; // Read SDA when SCL is high
                endcase
                if (bit_counter == 0 && phase_ctr == 3) begin
                    next_state = SEND_NACK;
                end
            end

            SEND_NACK: begin
                // Master sends NACK after reading a byte to signal end of transfer
                sda_out = 1'b1; // NACK is SDA high
                sda_en = 1'b1;
                case (phase_ctr)
                    0, 1: scl_out = 1'b0;
                    2:    scl_out = 1'b1;
                    3:    next_state = STOP;
                endcase
            end

            STOP: begin
                // STOP condition: SDA goes high while SCL is high
                case (phase_ctr)
                    0: begin scl_out = 1'b0; sda_out = 1'b0; sda_en = 1'b1; end
                    1: begin scl_out = 1'b1; sda_out = 1'b0; sda_en = 1'b1; end
                    2: begin scl_out = 1'b1; sda_out = 1'b1; sda_en = 1'b1; end
                    default: next_state = IDLE;
                endcase
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // --- 4. Output Assignments ---
    assign I2C_SCL = scl_out;
    assign I2C_SDA = sda_en ? sda_out : 1'bz;
    assign busy = (state != IDLE);
    assign I2C_En = busy;
    assign data_out = rx_buffer;

endmodule