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

    // State machine states
    typedef enum logic [4:0] {
        IDLE,
        START,
        ADDR_HIGH,      // First byte: 11110xx0 (high bits of 10-bit address)
        ACK_ADDR_HIGH,
        ADDR_LOW,       // Second byte: xxxxxxxx (low 8 bits of 10-bit address)
        ACK_ADDR_LOW,
        RESTART,        // For read operations after addressing
        ADDR_READ,      // Read address byte: 11110xx1
        ACK_ADDR_READ,
        WRITE_DATA,
        ACK_WRITE,
        READ_DATA,
        NACK_READ,
        STOP
    } state_t;

    state_t current_state, next_state;

    // Clock divider parameters (adjust for desired I2C frequency)
    // For 100kHz I2C clock from system clock
    parameter CLK_DIVIDER = 250; // Assuming 100MHz system clock -> 100kHz I2C
    
    // Internal signals
    logic [7:0] clk_counter;
    logic       scl_enable;
    logic       scl_reg;
    logic       sda_out;
    logic       sda_enable;
    logic       sda_in;
    logic [3:0] bit_counter;
    logic [7:0] shift_reg;
    logic [7:0] addr_high_byte;
    logic [7:0] addr_low_byte;
    logic       ack_received;
    logic       transaction_rw;
    logic [9:0] addr_reg;
    logic [7:0] data_reg;

    // Clock generation for I2C SCL
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 8'h0;
            scl_enable <= 1'b0;
        end else begin
            if (clk_counter >= (CLK_DIVIDER/4 - 1)) begin
                clk_counter <= 8'h0;
                scl_enable <= 1'b1;
            end else begin
                clk_counter <= clk_counter + 1'b1;
                scl_enable <= 1'b0;
            end
        end
    end

    // SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scl_reg <= 1'b1;
        end else if (scl_enable && (current_state != IDLE)) begin
            scl_reg <= ~scl_reg;
        end else if (current_state == IDLE) begin
            scl_reg <= 1'b1;
        end
    end

    // SDA bidirectional control
    assign I2C_SDA = sda_enable ? sda_out : 1'bz;
    assign sda_in = I2C_SDA;
    assign I2C_SCL = scl_reg;

    // Prepare 10-bit address bytes
    always_comb begin
        addr_high_byte = {5'b11110, slave_addr[9:8], 1'b0}; // High address byte for write
        addr_low_byte = slave_addr[7:0];                      // Low address byte
    end

    // State machine - sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            bit_counter <= 4'h0;
            shift_reg <= 8'h0;
            data_out <= 8'h0;
            ack_received <= 1'b0;
            transaction_rw <= 1'b0;
            addr_reg <= 10'h0;
            data_reg <= 8'h0;
        end else begin
            current_state <= next_state;
            
            // Store transaction parameters at start
            if (current_state == IDLE && I2C_Start) begin
                transaction_rw <= RW;
                addr_reg <= slave_addr;
                data_reg <= data_in;
            end
            
            // Handle bit counting and shifting
            if (scl_enable && scl_reg) begin // On SCL rising edge
                case (current_state)
                    ADDR_HIGH, ADDR_LOW, ADDR_READ, WRITE_DATA: begin
                        if (bit_counter < 7) begin
                            bit_counter <= bit_counter + 1'b1;
                            shift_reg <= {shift_reg[6:0], 1'b0};
                        end else begin
                            bit_counter <= 4'h0;
                        end
                    end
                    
                    READ_DATA: begin
                        if (bit_counter < 7) begin
                            bit_counter <= bit_counter + 1'b1;
                            shift_reg <= {shift_reg[6:0], sda_in};
                        end else begin
                            bit_counter <= 4'h0;
                            data_out <= {shift_reg[6:0], sda_in};
                        end
                    end
                    
                    ACK_ADDR_HIGH, ACK_ADDR_LOW, ACK_ADDR_READ, ACK_WRITE: begin
                        ack_received <= ~sda_in; // ACK is low
                    end
                    
                    default: begin
                        bit_counter <= 4'h0;
                    end
                endcase
            end
            
            // Load shift register at start of transmission states
            if (scl_enable && ~scl_reg && bit_counter == 0) begin // On SCL falling edge
                case (next_state)
                    ADDR_HIGH: shift_reg <= addr_high_byte;
                    ADDR_LOW: shift_reg <= addr_low_byte;
                    ADDR_READ: shift_reg <= {5'b11110, addr_reg[9:8], 1'b1};
                    WRITE_DATA: shift_reg <= data_reg;
                    READ_DATA: shift_reg <= 8'h0;
                    default: shift_reg <= shift_reg;
                endcase
            end
        end
    end

    // State machine - combinational logic
    always_comb begin
        next_state = current_state;
        sda_out = 1'b1;
        sda_enable = 1'b0;
        busy = 1'b0;
        I2C_En = 1'b0;
        
        case (current_state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START;
                    busy = 1'b1;
                    I2C_En = 1'b1;
                end
            end
            
            START: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b1;
                sda_out = 1'b0; // Start condition: SDA low while SCL high
                if (scl_enable) begin
                    next_state = ADDR_HIGH;
                end
            end
            
            ADDR_HIGH: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b1;
                sda_out = shift_reg[7];
                if (bit_counter == 7 && scl_enable && scl_reg) begin
                    next_state = ACK_ADDR_HIGH;
                end
            end
            
            ACK_ADDR_HIGH: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b0; // Release SDA for ACK
                if (scl_enable && scl_reg) begin
                    next_state = ADDR_LOW;
                end
            end
            
            ADDR_LOW: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b1;
                sda_out = shift_reg[7];
                if (bit_counter == 7 && scl_enable && scl_reg) begin
                    next_state = ACK_ADDR_LOW;
                end
            end
            
            ACK_ADDR_LOW: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b0; // Release SDA for ACK
                if (scl_enable && scl_reg) begin
                    if (transaction_rw) begin
                        next_state = RESTART;
                    end else begin
                        next_state = WRITE_DATA;
                    end
                end
            end
            
            RESTART: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b1;
                sda_out = 1'b0; // Repeated start condition
                if (scl_enable) begin
                    next_state = ADDR_READ;
                end
            end
            
            ADDR_READ: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b1;
                sda_out = shift_reg[7];
                if (bit_counter == 7 && scl_enable && scl_reg) begin
                    next_state = ACK_ADDR_READ;
                end
            end
            
            ACK_ADDR_READ: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b0; // Release SDA for ACK
                if (scl_enable && scl_reg) begin
                    next_state = READ_DATA;
                end
            end
            
            WRITE_DATA: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b1;
                sda_out = shift_reg[7];
                if (bit_counter == 7 && scl_enable && scl_reg) begin
                    next_state = ACK_WRITE;
                end
            end
            
            ACK_WRITE: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b0; // Release SDA for ACK
                if (scl_enable && scl_reg) begin
                    next_state = STOP;
                end
            end
            
            READ_DATA: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b0; // Release SDA for slave to drive
                if (bit_counter == 7 && scl_enable && scl_reg) begin
                    next_state = NACK_READ;
                end
            end
            
            NACK_READ: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b1;
                sda_out = 1'b1; // NACK (high) to indicate end of read
                if (scl_enable && scl_reg) begin
                    next_state = STOP;
                end
            end
            
            STOP: begin
                busy = 1'b1;
                I2C_En = 1'b1;
                sda_enable = 1'b1;
                sda_out = 1'b1; // Stop condition: SDA high while SCL high
                if (scl_enable) begin
                    next_state = IDLE;
                end
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule