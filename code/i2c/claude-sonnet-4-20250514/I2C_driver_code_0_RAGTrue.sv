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

    // State definitions
    typedef enum logic [4:0] {
        IDLE        = 5'b00000,
        START       = 5'b00001,
        ADDR_SETUP  = 5'b00010,
        ADDR_TRANS  = 5'b00011,
        ADDR_ACK    = 5'b00100,
        DATA_SETUP  = 5'b00101,
        DATA_TRANS  = 5'b00110,
        DATA_ACK    = 5'b00111,
        DATA_READ   = 5'b01000,
        MASTER_ACK  = 5'b01001,
        STOP        = 5'b01010,
        ERROR       = 5'b01011
    } state_t;

    // Internal signals
    state_t current_state, next_state;
    
    // Clock divider signals
    logic [7:0] clk_div_counter;
    logic       scl_enable;
    logic       scl_reg;
    
    // SDA control signals
    logic       sda_out;
    logic       sda_dir;  // 1 for output, 0 for input
    
    // Data handling
    logic [7:0] addr_byte;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic [2:0] bit_counter;
    
    // Control signals
    logic       start_detected;
    logic       ack_received;
    logic       transaction_complete;
    
    // Clock generation parameters
    parameter CLK_DIVIDER = 100; // Adjust based on system clock to get ~100kHz I2C clock
    
    //===========================================
    // Clock Divider for I2C SCL Generation
    //===========================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_counter <= 8'b0;
            scl_enable <= 1'b0;
        end else begin
            if (clk_div_counter >= (CLK_DIVIDER/4 - 1)) begin
                clk_div_counter <= 8'b0;
                scl_enable <= 1'b1;
            end else begin
                clk_div_counter <= clk_div_counter + 1;
                scl_enable <= 1'b0;
            end
        end
    end
    
    //===========================================
    // SCL Generation
    //===========================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            scl_reg <= 1'b1;
        end else if (scl_enable) begin
            case (current_state)
                IDLE, ERROR: 
                    scl_reg <= 1'b1;
                START: 
                    scl_reg <= 1'b1;
                ADDR_SETUP, DATA_SETUP: 
                    scl_reg <= 1'b0;
                ADDR_TRANS, DATA_TRANS, DATA_READ: 
                    scl_reg <= ~scl_reg;
                ADDR_ACK, DATA_ACK, MASTER_ACK: 
                    scl_reg <= ~scl_reg;
                STOP: 
                    scl_reg <= 1'b1;
                default: 
                    scl_reg <= 1'b1;
            endcase
        end
    end
    
    assign I2C_SCL = scl_reg;
    
    //===========================================
    // State Machine
    //===========================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else if (scl_enable) begin
            current_state <= next_state;
        end
    end
    
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START;
                end
            end
            
            START: begin
                next_state = ADDR_SETUP;
            end
            
            ADDR_SETUP: begin
                next_state = ADDR_TRANS;
            end
            
            ADDR_TRANS: begin
                if (bit_counter == 3'b111 && scl_reg == 1'b0) begin
                    next_state = ADDR_ACK;
                end
            end
            
            ADDR_ACK: begin
                if (scl_reg == 1'b0) begin
                    if (ack_received) begin
                        if (RW) begin
                            next_state = DATA_READ;
                        end else begin
                            next_state = DATA_SETUP;
                        end
                    end else begin
                        next_state = ERROR;
                    end
                end
            end
            
            DATA_SETUP: begin
                next_state = DATA_TRANS;
            end
            
            DATA_TRANS: begin
                if (bit_counter == 3'b111 && scl_reg == 1'b0) begin
                    next_state = DATA_ACK;
                end
            end
            
            DATA_ACK: begin
                if (scl_reg == 1'b0) begin
                    if (ack_received) begin
                        next_state = STOP;
                    end else begin
                        next_state = ERROR;
                    end
                end
            end
            
            DATA_READ: begin
                if (bit_counter == 3'b111 && scl_reg == 1'b0) begin
                    next_state = MASTER_ACK;
                end
            end
            
            MASTER_ACK: begin
                if (scl_reg == 1'b0) begin
                    next_state = STOP;
                end
            end
            
            STOP: begin
                next_state = IDLE;
            end
            
            ERROR: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    //===========================================
    // Data Handling and Bit Counter
    //===========================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 3'b0;
            addr_byte <= 8'b0;
            tx_data <= 8'b0;
            rx_data <= 8'b0;
            ack_received <= 1'b0;
        end else if (scl_enable) begin
            case (current_state)
                IDLE: begin
                    bit_counter <= 3'b0;
                    addr_byte <= {slave_addr, RW};
                    tx_data <= data_in;
                    rx_data <= 8'b0;
                end
                
                START: begin
                    bit_counter <= 3'b0;
                end
                
                ADDR_SETUP: begin
                    bit_counter <= 3'b0;
                end
                
                ADDR_TRANS: begin
                    if (scl_reg == 1'b1) begin
                        bit_counter <= bit_counter + 1;
                    end
                end
                
                ADDR_ACK: begin
                    if (scl_reg == 1'b1) begin
                        ack_received <= ~I2C_SDA;
                    end
                    bit_counter <= 3'b0;
                end
                
                DATA_SETUP: begin
                    bit_counter <= 3'b0;
                end
                
                DATA_TRANS: begin
                    if (scl_reg == 1'b1) begin
                        bit_counter <= bit_counter + 1;
                    end
                end
                
                DATA_ACK: begin
                    if (scl_reg == 1'b1) begin
                        ack_received <= ~I2C_SDA;
                    end
                end
                
                DATA_READ: begin
                    if (scl_reg == 1'b1) begin
                        rx_data <= {rx_data[6:0], I2C_SDA};
                        bit_counter <= bit_counter + 1;
                    end
                end
                
                MASTER_ACK: begin
                    // Master sends NACK for single byte read
                    bit_counter <= 3'b0;
                end
                
                default: begin
                    bit_counter <= 3'b0;
                end
            endcase
        end
    end
    
    //===========================================
    // SDA Control Logic
    //===========================================
    always_comb begin
        sda_dir = 1'b1; // Default to output
        sda_out = 1'b1; // Default to high
        
        case (current_state)
            IDLE: begin
                sda_dir = 1'b1;
                sda_out = 1'b1;
            end
            
            START: begin
                sda_dir = 1'b1;
                sda_out = 1'b0; // Start condition: SDA goes low while SCL is high
            end
            
            ADDR_TRANS: begin
                sda_dir = 1'b1;
                sda_out = addr_byte[7 - bit_counter];
            end
            
            ADDR_ACK: begin
                sda_dir = 1'b0; // Input to receive ACK
                sda_out = 1'b1;
            end
            
            DATA_TRANS: begin
                sda_dir = 1'b1;
                sda_out = tx_data[7 - bit_counter];
            end
            
            DATA_ACK: begin
                sda_dir = 1'b0; // Input to receive ACK
                sda_out = 1'b1;
            end
            
            DATA_READ: begin
                sda_dir = 1'b0; // Input to read data
                sda_out = 1'b1;
            end
            
            MASTER_ACK: begin
                sda_dir = 1'b1;
                sda_out = 1'b1; // Send NACK (high)
            end
            
            STOP: begin
                sda_dir = 1'b1;
                sda_out = 1'b1; // Stop condition: SDA goes high while SCL is high
            end
            
            ERROR: begin
                sda_dir = 1'b1;
                sda_out = 1'b1;
            end
            
            default: begin
                sda_dir = 1'b1;
                sda_out = 1'b1;
            end
        endcase
    end
    
    //===========================================
    // Bidirectional SDA Control
    //===========================================
    assign I2C_SDA = sda_dir ? sda_out : 1'bz;
    
    //===========================================
    // Output Assignments
    //===========================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'b0;
            busy <= 1'b0;
            I2C_En <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                    if (next_state == START) begin
                        busy <= 1'b1;
                        I2C_En <= 1'b1;
                    end
                end
                
                STOP: begin
                    data_out <= rx_data;
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                end
                
                ERROR: begin
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                end
                
                default: begin
                    busy <= 1'b1;
                    I2C_En <= 1'b1;
                end
            endcase
        end
    end

endmodule