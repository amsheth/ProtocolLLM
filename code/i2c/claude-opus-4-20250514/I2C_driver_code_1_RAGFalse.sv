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

    // Clock divider parameters (adjust based on system clock and desired I2C frequency)
    parameter CLK_DIV = 100;  // For 100MHz system clock -> 250kHz SCL (standard mode)
    
    // State machine states
    typedef enum logic [4:0] {
        IDLE,
        START,
        SEND_ADDR_HIGH,
        CHECK_ADDR_ACK1,
        SEND_ADDR_LOW,
        CHECK_ADDR_ACK2,
        WRITE_DATA,
        CHECK_DATA_ACK,
        READ_DATA,
        SEND_ACK,
        SEND_NACK,
        STOP,
        HOLD_STOP
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal signals
    logic [7:0] clk_div_cnt;
    logic clk_pulse;
    logic scl_enable;
    logic sda_out;
    logic sda_oe;  // SDA output enable
    logic [3:0] bit_cnt;
    logic [7:0] addr_high_byte;
    logic [7:0] addr_low_byte;
    logic [7:0] data_buffer;
    logic ack_received;
    
    // Clock divider for I2C clock generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_cnt <= '0;
            clk_pulse <= 1'b0;
        end else begin
            if (clk_div_cnt >= CLK_DIV - 1) begin
                clk_div_cnt <= '0;
                clk_pulse <= 1'b1;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1'b1;
                clk_pulse <= 1'b0;
            end
        end
    end
    
    // SCL generation
    logic scl_clk;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scl_clk <= 1'b1;
        end else if (clk_pulse) begin
            if (scl_enable)
                scl_clk <= ~scl_clk;
            else
                scl_clk <= 1'b1;
        end
    end
    
    assign I2C_SCL = scl_clk;
    
    // Bidirectional SDA handling
    assign I2C_SDA = sda_oe ? sda_out : 1'bz;
    
    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (I2C_Start)
                    next_state = START;
            end
            
            START: begin
                if (clk_pulse && scl_clk)
                    next_state = SEND_ADDR_HIGH;
            end
            
            SEND_ADDR_HIGH: begin
                if (clk_pulse && !scl_clk && bit_cnt == 8)
                    next_state = CHECK_ADDR_ACK1;
            end
            
            CHECK_ADDR_ACK1: begin
                if (clk_pulse && !scl_clk)
                    next_state = SEND_ADDR_LOW;
            end
            
            SEND_ADDR_LOW: begin
                if (clk_pulse && !scl_clk && bit_cnt == 8)
                    next_state = CHECK_ADDR_ACK2;
            end
            
            CHECK_ADDR_ACK2: begin
                if (clk_pulse && !scl_clk) begin
                    if (RW)
                        next_state = READ_DATA;
                    else
                        next_state = WRITE_DATA;
                end
            end
            
            WRITE_DATA: begin
                if (clk_pulse && !scl_clk && bit_cnt == 8)
                    next_state = CHECK_DATA_ACK;
            end
            
            CHECK_DATA_ACK: begin
                if (clk_pulse && !scl_clk)
                    next_state = STOP;
            end
            
            READ_DATA: begin
                if (clk_pulse && !scl_clk && bit_cnt == 8)
                    next_state = SEND_NACK;
            end
            
            SEND_NACK: begin
                if (clk_pulse && !scl_clk)
                    next_state = STOP;
            end
            
            STOP: begin
                if (clk_pulse && scl_clk)
                    next_state = HOLD_STOP;
            end
            
            HOLD_STOP: begin
                if (clk_pulse)
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Output and control logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sda_out <= 1'b1;
            sda_oe <= 1'b0;
            bit_cnt <= '0;
            data_buffer <= '0;
            data_out <= '0;
            busy <= 1'b0;
            I2C_En <= 1'b0;
            scl_enable <= 1'b0;
            addr_high_byte <= '0;
            addr_low_byte <= '0;
        end else begin
            case (current_state)
                IDLE: begin
                    sda_out <= 1'b1;
                    sda_oe <= 1'b1;
                    bit_cnt <= '0;
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                    scl_enable <= 1'b0;
                    if (I2C_Start) begin
                        busy <= 1'b1;
                        I2C_En <= 1'b1;
                        // Prepare 10-bit address format
                        addr_high_byte <= {5'b11110, slave_addr[9:8], 1'b0}; // 10-bit addressing + W
                        addr_low_byte <= slave_addr[7:0];
                        data_buffer <= data_in;
                    end
                end
                
                START: begin
                    sda_oe <= 1'b1;
                    if (clk_pulse && scl_clk) begin
                        sda_out <= 1'b0;  // Start condition: SDA falls while SCL is high
                        scl_enable <= 1'b1;
                    end
                end
                
                SEND_ADDR_HIGH: begin
                    sda_oe <= 1'b1;
                    if (clk_pulse && !scl_clk) begin
                        if (bit_cnt < 8) begin
                            sda_out <= addr_high_byte[7 - bit_cnt];
                            bit_cnt <= bit_cnt + 1'b1;
                        end else begin
                            bit_cnt <= '0;
                        end
                    end
                end
                
                CHECK_ADDR_ACK1: begin
                    sda_oe <= 1'b0;  // Release SDA for slave ACK
                    if (clk_pulse && scl_clk) begin
                        ack_received <= !I2C_SDA;  // ACK is low
                    end
                end
                
                SEND_ADDR_LOW: begin
                    sda_oe <= 1'b1;
                    if (clk_pulse && !scl_clk) begin
                        if (bit_cnt < 8) begin
                            sda_out <= addr_low_byte[7 - bit_cnt];
                            bit_cnt <= bit_cnt + 1'b1;
                        end else begin
                            bit_cnt <= '0;
                        end
                    end
                end
                
                CHECK_ADDR_ACK2: begin
                    sda_oe <= 1'b0;  // Release SDA for slave ACK
                    if (clk_pulse && scl_clk) begin
                        ack_received <= !I2C_SDA;
                    end
                end
                
                WRITE_DATA: begin
                    sda_oe <= 1'b1;
                    if (clk_pulse && !scl_clk) begin
                        if (bit_cnt < 8) begin
                            sda_out <= data_buffer[7 - bit_cnt];
                            bit_cnt <= bit_cnt + 1'b1;
                        end else begin
                            bit_cnt <= '0;
                        end
                    end
                end
                
                CHECK_DATA_ACK: begin
                    sda_oe <= 1'b0;  // Release SDA for slave ACK
                    if (clk_pulse && scl_clk) begin
                        ack_received <= !I2C_SDA;
                    end
                end
                
                READ_DATA: begin
                    sda_oe <= 1'b0;  // Release SDA for slave to drive
                    if (clk_pulse && scl_clk) begin
                        if (bit_cnt < 8) begin
                            data_out[7 - bit_cnt] <= I2C_SDA;
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else if (clk_pulse && !scl_clk && bit_cnt == 8) begin
                        bit_cnt <= '0;
                    end
                end
                
                SEND_NACK: begin
                    sda_oe <= 1'b1;
                    sda_out <= 1'b1;  // NACK (high)
                end
                
                STOP: begin
                    sda_oe <= 1'b1;
                    if (clk_pulse && !scl_clk) begin
                        sda_out <= 1'b0;  // Prepare for stop condition
                    end else if (clk_pulse && scl_clk) begin
                        sda_out <= 1'b1;  // Stop condition: SDA rises while SCL is high
                    end
                end
                
                HOLD_STOP: begin
                    sda_oe <= 1'b1;
                    sda_out <= 1'b1;
                    scl_enable <= 1'b0;
                end
            endcase
        end
    end

endmodule