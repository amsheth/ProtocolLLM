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

    // State machine definitions
    typedef enum logic [4:0] {
        IDLE           = 5'b00000,
        START          = 5'b00001,
        ADDR_FIRST     = 5'b00010,
        ADDR_FIRST_ACK = 5'b00011,
        ADDR_SECOND    = 5'b00100,
        ADDR_SECOND_ACK= 5'b00101,
        WRITE_DATA     = 5'b00110,
        WRITE_ACK      = 5'b00111,
        READ_DATA      = 5'b01000,
        READ_ACK       = 5'b01001,
        STOP           = 5'b01010,
        COMPLETE       = 5'b01011
    } state_t;

    state_t current_state, next_state;

    // Clock divider for I2C SCL generation
    // Assuming 100 MHz system clock, targeting 100 kHz I2C clock
    // Clock divider value = 100MHz / (100kHz * 4) = 250
    // We divide by 4 because we need 4 clock phases for each SCL period
    localparam CLK_DIVIDER = 250;
    localparam CLK_COUNTER_WIDTH = $clog2(CLK_DIVIDER);
    
    logic [CLK_COUNTER_WIDTH-1:0] clk_counter;
    logic [1:0] scl_phase;  // 4 phases: 00, 01, 10, 11
    logic scl_tick;
    
    // I2C signals
    logic sda_out, sda_oe;  // SDA output and output enable
    logic scl_out;
    
    // Internal registers
    logic [10:0] addr_shift_reg;  // 11 bits: 10-bit addr + R/W bit
    logic [7:0] data_shift_reg;
    logic [7:0] read_data_reg;
    logic [3:0] bit_counter;
    logic ack_received;
    logic transaction_rw;
    
    // Bidirectional SDA handling
    assign I2C_SDA = sda_oe ? sda_out : 1'bz;
    assign I2C_SCL = scl_out;
    
    // Clock divider and SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 0;
            scl_phase <= 2'b00;
            scl_tick <= 1'b0;
        end else begin
            scl_tick <= 1'b0;
            if (clk_counter >= CLK_DIVIDER - 1) begin
                clk_counter <= 0;
                scl_phase <= scl_phase + 1;
                scl_tick <= 1'b1;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end
    end
    
    // SCL generation based on phase
    always_comb begin
        case (scl_phase)
            2'b00, 2'b01: scl_out = 1'b0;  // SCL low
            2'b10, 2'b11: scl_out = 1'b1;  // SCL high
        endcase
    end
    
    // State machine - sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // State machine - combinational logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START;
                end
            end
            
            START: begin
                if (scl_tick && scl_phase == 2'b01) begin
                    next_state = ADDR_FIRST;
                end
            end
            
            ADDR_FIRST: begin
                if (scl_tick && scl_phase == 2'b01 && bit_counter == 0) begin
                    next_state = ADDR_FIRST_ACK;
                end
            end
            
            ADDR_FIRST_ACK: begin
                if (scl_tick && scl_phase == 2'b01) begin
                    if (ack_received) begin
                        next_state = ADDR_SECOND;
                    end else begin
                        next_state = STOP;  // NACK received, abort
                    end
                end
            end
            
            ADDR_SECOND: begin
                if (scl_tick && scl_phase == 2'b01 && bit_counter == 0) begin
                    next_state = ADDR_SECOND_ACK;
                end
            end
            
            ADDR_SECOND_ACK: begin
                if (scl_tick && scl_phase == 2'b01) begin
                    if (ack_received) begin
                        if (transaction_rw) begin
                            next_state = READ_DATA;
                        end else begin
                            next_state = WRITE_DATA;
                        end
                    end else begin
                        next_state = STOP;  // NACK received, abort
                    end
                end
            end
            
            WRITE_DATA: begin
                if (scl_tick && scl_phase == 2'b01 && bit_counter == 0) begin
                    next_state = WRITE_ACK;
                end
            end
            
            WRITE_ACK: begin
                if (scl_tick && scl_phase == 2'b01) begin
                    next_state = STOP;
                end
            end
            
            READ_DATA: begin
                if (scl_tick && scl_phase == 2'b01 && bit_counter == 0) begin
                    next_state = READ_ACK;
                end
            end
            
            READ_ACK: begin
                if (scl_tick && scl_phase == 2'b01) begin
                    next_state = STOP;
                end
            end
            
            STOP: begin
                if (scl_tick && scl_phase == 2'b01) begin
                    next_state = COMPLETE;
                end
            end
            
            COMPLETE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Control logic and data handling
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sda_out <= 1'b1;
            sda_oe <= 1'b1;
            addr_shift_reg <= 11'b0;
            data_shift_reg <= 8'b0;
            read_data_reg <= 8'b0;
            bit_counter <= 4'b0;
            ack_received <= 1'b0;
            transaction_rw <= 1'b0;
            data_out <= 8'b0;
            busy <= 1'b0;
            I2C_En <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    sda_out <= 1'b1;
                    sda_oe <= 1'b1;
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                    if (I2C_Start) begin
                        // Prepare for transaction
                        addr_shift_reg <= {1'b1, 1'b1, 1'b1, 1'b1, 1'b0, slave_addr[9:6], 1'b0}; // First byte: 11110XX0
                        data_shift_reg <= {slave_addr[5:0], RW, 1'b0}; // Second byte: lower 6 bits + R/W
                        transaction_rw <= RW;
                        busy <= 1'b1;
                        I2C_En <= 1'b1;
                    end
                end
                
                START: begin
                    if (scl_tick && scl_phase == 2'b11) begin
                        // Generate start condition: SDA goes low while SCL is high
                        sda_out <= 1'b0;
                        bit_counter <= 4'd7;  // Prepare for 8-bit transmission
                    end
                end
                
                ADDR_FIRST: begin
                    if (scl_tick) begin
                        case (scl_phase)
                            2'b00: begin
                                // Setup data during SCL low
                                sda_out <= addr_shift_reg[bit_counter];
                                sda_oe <= 1'b1;
                            end
                            2'b01: begin
                                // Data should be stable during SCL low to high transition
                                if (bit_counter > 0) begin
                                    bit_counter <= bit_counter - 1;
                                end else begin
                                    // Prepare for ACK
                                    sda_oe <= 1'b0;  // Release SDA for slave ACK
                                end
                            end
                        endcase
                    end
                end
                
                ADDR_FIRST_ACK: begin
                    if (scl_tick && scl_phase == 2'b10) begin
                        // Sample ACK during SCL high
                        ack_received <= ~I2C_SDA;
                    end else if (scl_tick && scl_phase == 2'b01) begin
                        // Prepare for next byte
                        sda_oe <= 1'b1;
                        bit_counter <= 4'd7;
                    end
                end
                
                ADDR_SECOND: begin
                    if (scl_tick) begin
                        case (scl_phase)
                            2'b00: begin
                                sda_out <= data_shift_reg[bit_counter];
                                sda_oe <= 1'b1;
                            end
                            2'b01: begin
                                if (bit_counter > 0) begin
                                    bit_counter <= bit_counter - 1;
                                end else begin
                                    sda_oe <= 1'b0;  // Release SDA for slave ACK
                                end
                            end
                        endcase
                    end
                end
                
                ADDR_SECOND_ACK: begin
                    if (scl_tick && scl_phase == 2'b10) begin
                        ack_received <= ~I2C_SDA;
                    end else if (scl_tick && scl_phase == 2'b01) begin
                        sda_oe <= 1'b1;
                        bit_counter <= 4'd7;
                        if (transaction_rw == 1'b0) begin
                            // Prepare write data
                            data_shift_reg <= data_in;
                        end
                    end
                end
                
                WRITE_DATA: begin
                    if (scl_tick) begin
                        case (scl_phase)
                            2'b00: begin
                                sda_out <= data_shift_reg[bit_counter];
                                sda_oe <= 1'b1;
                            end
                            2'b01: begin
                                if (bit_counter > 0) begin
                                    bit_counter <= bit_counter - 1;
                                end else begin
                                    sda_oe <= 1'b0;  // Release SDA for slave ACK
                                end
                            end
                        endcase
                    end
                end
                
                WRITE_ACK: begin
                    if (scl_tick && scl_phase == 2'b10) begin
                        ack_received <= ~I2C_SDA;
                    end else if (scl_tick && scl_phase == 2'b01) begin
                        sda_oe <= 1'b1;
                    end
                end
                
                READ_DATA: begin
                    if (scl_tick) begin
                        case (scl_phase)
                            2'b00: begin
                                sda_oe <= 1'b0;  // Release SDA for slave data
                            end
                            2'b10: begin
                                // Sample data during SCL high
                                read_data_reg[bit_counter] <= I2C_SDA;
                            end
                            2'b01: begin
                                if (bit_counter > 0) begin
                                    bit_counter <= bit_counter - 1;
                                end else begin
                                    data_out <= read_data_reg;
                                end
                            end
                        endcase
                    end
                end
                
                READ_ACK: begin
                    if (scl_tick) begin
                        case (scl_phase)
                            2'b00: begin
                                // Send NACK to indicate end of read
                                sda_out <= 1'b1;
                                sda_oe <= 1'b1;
                            end
                        endcase
                    end
                end
                
                STOP: begin
                    if (scl_tick) begin
                        case (scl_phase)
                            2'b00: begin
                                sda_out <= 1'b0;
                                sda_oe <= 1'b1;
                            end
                            2'b10: begin
                                // Generate stop condition: SDA goes high while SCL is high
                                sda_out <= 1'b1;
                            end
                        endcase
                    end
                end
                
                COMPLETE: begin
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                end
            endcase
        end
    end

endmodule