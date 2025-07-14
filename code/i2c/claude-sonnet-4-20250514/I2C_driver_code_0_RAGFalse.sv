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

    // State machine states
    typedef enum logic [4:0] {
        IDLE         = 5'b00000,
        START        = 5'b00001,
        ADDR_SEND    = 5'b00010,
        ADDR_ACK     = 5'b00011,
        DATA_SEND    = 5'b00100,
        DATA_ACK     = 5'b00101,
        DATA_READ    = 5'b00110,
        DATA_NACK    = 5'b00111,
        STOP         = 5'b01000,
        COMPLETE     = 5'b01001
    } state_t;

    // Internal signals
    state_t current_state, next_state;
    logic [7:0] clk_divider;
    logic       i2c_clk_en;
    logic       sda_out;
    logic       sda_oe;        // SDA output enable
    logic [3:0] bit_counter;
    logic [7:0] shift_reg;
    logic [7:0] addr_byte;
    logic       ack_received;
    logic       start_condition;
    logic       i2c_start_sync;
    logic       i2c_start_prev;
    
    // Clock divider parameters (adjust based on system clock frequency)
    // For 100kHz I2C with 50MHz system clock: divide by 500
    // For 400kHz I2C with 50MHz system clock: divide by 125
    parameter CLK_DIVIDER = 8'd125; // Adjust based on desired I2C frequency
    
    // Clock divider for I2C SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_divider <= 8'd0;
            i2c_clk_en <= 1'b0;
        end else begin
            if (clk_divider >= (CLK_DIVIDER - 1)) begin
                clk_divider <= 8'd0;
                i2c_clk_en <= 1'b1;
            end else begin
                clk_divider <= clk_divider + 1'b1;
                i2c_clk_en <= 1'b0;
            end
        end
    end
    
    // Input synchronization
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            i2c_start_prev <= 1'b0;
            i2c_start_sync <= 1'b0;
        end else begin
            i2c_start_prev <= I2C_Start;
            i2c_start_sync <= I2C_Start && !i2c_start_prev; // Edge detection
        end
    end
    
    // State machine - sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else if (i2c_clk_en) begin
            current_state <= next_state;
        end
    end
    
    // State machine - combinational logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (i2c_start_sync) begin
                    next_state = START;
                end
            end
            
            START: begin
                next_state = ADDR_SEND;
            end
            
            ADDR_SEND: begin
                if (bit_counter == 4'd7) begin
                    next_state = ADDR_ACK;
                end
            end
            
            ADDR_ACK: begin
                if (RW) begin
                    next_state = DATA_READ;
                end else begin
                    next_state = DATA_SEND;
                end
            end
            
            DATA_SEND: begin
                if (bit_counter == 4'd7) begin
                    next_state = DATA_ACK;
                end
            end
            
            DATA_ACK: begin
                next_state = STOP;
            end
            
            DATA_READ: begin
                if (bit_counter == 4'd7) begin
                    next_state = DATA_NACK;
                end
            end
            
            DATA_NACK: begin
                next_state = STOP;
            end
            
            STOP: begin
                next_state = COMPLETE;
            end
            
            COMPLETE: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Bit counter management
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
        end else if (i2c_clk_en) begin
            if (current_state == ADDR_SEND || current_state == DATA_SEND || current_state == DATA_READ) begin
                bit_counter <= bit_counter + 1'b1;
            end else begin
                bit_counter <= 4'd0;
            end
        end
    end
    
    // Address byte preparation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            addr_byte <= 8'd0;
        end else if (current_state == IDLE && i2c_start_sync) begin
            addr_byte <= {slave_addr, RW};
        end
    end
    
    // Shift register for data transmission/reception
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 8'd0;
        end else if (i2c_clk_en) begin
            case (current_state)
                START: begin
                    shift_reg <= addr_byte;
                end
                
                ADDR_SEND: begin
                    shift_reg <= {shift_reg[6:0], 1'b0};
                end
                
                ADDR_ACK: begin
                    if (RW) begin
                        shift_reg <= 8'd0; // Prepare for reading
                    end else begin
                        shift_reg <= data_in; // Load data to send
                    end
                end
                
                DATA_SEND: begin
                    shift_reg <= {shift_reg[6:0], 1'b0};
                end
                
                DATA_READ: begin
                    shift_reg <= {shift_reg[6:0], I2C_SDA};
                end
            endcase
        end
    end
    
    // ACK detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ack_received <= 1'b0;
        end else if (i2c_clk_en) begin
            if (current_state == ADDR_ACK || current_state == DATA_ACK) begin
                ack_received <= ~I2C_SDA; // ACK is active low
            end
        end
    end
    
    // SDA control logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sda_out <= 1'b1;
            sda_oe <= 1'b0;
        end else if (i2c_clk_en) begin
            case (current_state)
                IDLE: begin
                    sda_out <= 1'b1;
                    sda_oe <= 1'b0;
                end
                
                START: begin
                    sda_out <= 1'b0; // Start condition: SDA low while SCL high
                    sda_oe <= 1'b1;
                end
                
                ADDR_SEND: begin
                    sda_out <= shift_reg[7];
                    sda_oe <= 1'b1;
                end
                
                ADDR_ACK: begin
                    sda_out <= 1'b1;
                    sda_oe <= 1'b0; // Release SDA for ACK
                end
                
                DATA_SEND: begin
                    sda_out <= shift_reg[7];
                    sda_oe <= 1'b1;
                end
                
                DATA_ACK: begin
                    sda_out <= 1'b1;
                    sda_oe <= 1'b0; // Release SDA for ACK
                end
                
                DATA_READ: begin
                    sda_out <= 1'b1;
                    sda_oe <= 1'b0; // Release SDA for slave to drive
                end
                
                DATA_NACK: begin
                    sda_out <= 1'b1; // NACK: SDA high during ACK clock
                    sda_oe <= 1'b1;
                end
                
                STOP: begin
                    sda_out <= 1'b1; // Stop condition: SDA high while SCL high
                    sda_oe <= 1'b1;
                end
                
                COMPLETE: begin
                    sda_out <= 1'b1;
                    sda_oe <= 1'b0;
                end
                
                default: begin
                    sda_out <= 1'b1;
                    sda_oe <= 1'b0;
                end
            endcase
        end
    end
    
    // SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            I2C_SCL <= 1'b1;
        end else if (i2c_clk_en) begin
            case (current_state)
                IDLE, COMPLETE: begin
                    I2C_SCL <= 1'b1;
                end
                
                START: begin
                    I2C_SCL <= 1'b1; // SCL stays high during start condition
                end
                
                STOP: begin
                    I2C_SCL <= 1'b1; // SCL goes high before stop condition
                end
                
                default: begin
                    I2C_SCL <= ~I2C_SCL; // Toggle SCL for data transfer
                end
            endcase
        end
    end
    
    // Output data register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'd0;
        end else if (i2c_clk_en && current_state == DATA_NACK) begin
            data_out <= shift_reg;
        end
    end
    
    // Control signals
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0;
            I2C_En <= 1'b0;
        end else begin
            busy <= (current_state != IDLE);
            I2C_En <= (current_state != IDLE && current_state != COMPLETE);
        end
    end
    
    // Bidirectional SDA control
    assign I2C_SDA = sda_oe ? sda_out : 1'bz;

endmodule