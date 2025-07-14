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

    // Clock divider parameters (adjust based on system clock and desired I2C speed)
    parameter CLK_DIV = 100;  // For 100kHz I2C from 10MHz system clock
    
    // State machine states
    typedef enum logic [3:0] {
        IDLE,
        START,
        ADDR,
        ADDR_ACK,
        DATA_WRITE,
        DATA_WRITE_ACK,
        DATA_READ,
        DATA_READ_ACK,
        STOP,
        DONE
    } state_t;
    
    state_t state, next_state;
    
    // Internal registers
    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic [7:0] clk_div_cnt;
    logic scl_en, sda_en;
    logic sda_out;
    logic [1:0] scl_phase;  // 4 phases per SCL cycle
    logic ack_received;
    
    // Clock generation for I2C SCL
    logic scl_tick;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_cnt <= 8'd0;
            scl_tick <= 1'b0;
        end else begin
            if (clk_div_cnt >= CLK_DIV - 1) begin
                clk_div_cnt <= 8'd0;
                scl_tick <= 1'b1;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1'b1;
                scl_tick <= 1'b0;
            end
        end
    end
    
    // SCL phase counter (4 phases per bit)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scl_phase <= 2'd0;
        end else if (scl_tick && scl_en) begin
            scl_phase <= scl_phase + 1'b1;
        end else if (!scl_en) begin
            scl_phase <= 2'd0;
        end
    end
    
    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (I2C_Start)
                    next_state = START;
            end
            
            START: begin
                if (scl_tick && scl_phase == 2'd3)
                    next_state = ADDR;
            end
            
            ADDR: begin
                if (scl_tick && scl_phase == 2'd3 && bit_cnt == 3'd0)
                    next_state = ADDR_ACK;
            end
            
            ADDR_ACK: begin
                if (scl_tick && scl_phase == 2'd3) begin
                    if (!ack_received)
                        next_state = STOP;  // NACK received, abort
                    else if (RW)
                        next_state = DATA_READ;
                    else
                        next_state = DATA_WRITE;
                end
            end
            
            DATA_WRITE: begin
                if (scl_tick && scl_phase == 2'd3 && bit_cnt == 3'd0)
                    next_state = DATA_WRITE_ACK;
            end
            
            DATA_WRITE_ACK: begin
                if (scl_tick && scl_phase == 2'd3)
                    next_state = STOP;
            end
            
            DATA_READ: begin
                if (scl_tick && scl_phase == 2'd3 && bit_cnt == 3'd0)
                    next_state = DATA_READ_ACK;
            end
            
            DATA_READ_ACK: begin
                if (scl_tick && scl_phase == 2'd3)
                    next_state = STOP;
            end
            
            STOP: begin
                if (scl_tick && scl_phase == 2'd3)
                    next_state = DONE;
            end
            
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Bit counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt <= 3'd7;
        end else if ((state == ADDR || state == DATA_WRITE || state == DATA_READ) && 
                     scl_tick && scl_phase == 2'd3) begin
            bit_cnt <= bit_cnt - 1'b1;
        end else if (state == START || state == ADDR_ACK || state == DATA_WRITE_ACK || 
                     state == DATA_READ_ACK) begin
            bit_cnt <= 3'd7;
        end
    end
    
    // Shift register operations
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'd0;
            data_out <= 8'd0;
        end else begin
            case (state)
                START: begin
                    shift_reg <= {slave_addr, RW};
                end
                
                ADDR: begin
                    if (scl_tick && scl_phase == 2'd3)
                        shift_reg <= {shift_reg[6:0], 1'b0};
                end
                
                DATA_WRITE: begin
                    if (state != DATA_WRITE && next_state == DATA_WRITE)
                        shift_reg <= data_in;
                    else if (scl_tick && scl_phase == 2'd3)
                        shift_reg <= {shift_reg[6:0], 1'b0};
                end
                
                DATA_READ: begin
                    if (scl_tick && scl_phase == 2'd1)  // Sample on SCL high
                        shift_reg <= {shift_reg[6:0], I2C_SDA};
                end
                
                DATA_READ_ACK: begin
                    data_out <= shift_reg;
                end
            endcase
        end
    end
    
    // ACK detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ack_received <= 1'b0;
        end else if ((state == ADDR_ACK || state == DATA_WRITE_ACK) && 
                     scl_tick && scl_phase == 2'd1) begin
            ack_received <= !I2C_SDA;  // ACK is low
        end
    end
    
    // SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            I2C_SCL <= 1'b1;
            scl_en <= 1'b0;
        end else begin
            case (state)
                IDLE, DONE: begin
                    I2C_SCL <= 1'b1;
                    scl_en <= 1'b0;
                end
                
                START: begin
                    scl_en <= 1'b1;
                    if (scl_tick) begin
                        case (scl_phase)
                            2'd0, 2'd1: I2C_SCL <= 1'b1;
                            2'd2, 2'd3: I2C_SCL <= 1'b1;
                        endcase
                    end
                end
                
                STOP: begin
                    if (scl_tick) begin
                        case (scl_phase)
                            2'd0: I2C_SCL <= 1'b0;
                            2'd1, 2'd2, 2'd3: I2C_SCL <= 1'b1;
                        endcase
                    end
                end
                
                default: begin  // Normal data/address transfer
                    scl_en <= 1'b1;
                    if (scl_tick) begin
                        case (scl_phase)
                            2'd0, 2'd3: I2C_SCL <= 1'b0;
                            2'd1, 2'd2: I2C_SCL <= 1'b1;
                        endcase
                    end
                end
            endcase
        end
    end
    
    // SDA control logic
    always_comb begin
        sda_out = 1'b1;
        sda_en = 1'b0;
        
        case (state)
            START: begin
                sda_en = 1'b1;
                if (scl_phase == 2'd0 || scl_phase == 2'd1)
                    sda_out = 1'b1;
                else
                    sda_out = 1'b0;  // START condition
            end
            
            ADDR, DATA_WRITE: begin
                sda_en = 1'b1;
                sda_out = shift_reg[7];
            end
            
            ADDR_ACK, DATA_WRITE_ACK: begin
                sda_en = 1'b0;  // Release SDA for slave ACK
            end
            
            DATA_READ: begin
                sda_en = 1'b0;  // Release SDA for slave to drive
            end
            
            DATA_READ_ACK: begin
                sda_en = 1'b1;
                sda_out = 1'b1;  // NACK to end read
            end
            
            STOP: begin
                sda_en = 1'b1;
                if (scl_phase == 2'd0 || scl_phase == 2'd1)
                    sda_out = 1'b0;
                else
                    sda_out = 1'b1;  // STOP condition
            end
            
            default: begin
                sda_en = 1'b0;
                sda_out = 1'b1;
            end
        endcase
    end
    
    // Bidirectional SDA control
    assign I2C_SDA = sda_en ? sda_out : 1'bz;
    
    // Output control signals
    assign busy = (state != IDLE);
    assign I2C_En = (state != IDLE) && (state != DONE);

endmodule