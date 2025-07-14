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

    // Clock divider parameters (adjust based on system clock and desired I2C frequency)
    localparam CLK_DIV = 100;  // For 100MHz system clock -> 100kHz I2C clock
    localparam CLK_DIV_HALF = CLK_DIV / 2;
    
    // State machine states
    typedef enum logic [3:0] {
        IDLE,
        START,
        SEND_ADDR,
        ADDR_ACK,
        SEND_DATA,
        DATA_ACK,
        READ_DATA,
        SEND_ACK,
        SEND_NACK,
        STOP,
        STOP_WAIT
    } state_t;
    
    state_t state, next_state;
    
    // Internal registers
    logic [7:0] clk_counter;
    logic       clk_pulse;
    logic       scl_enable;
    logic       sda_out;
    logic       sda_enable;  // 1 = drive SDA, 0 = high-Z (for reading)
    logic [7:0] shift_reg;
    logic [3:0] bit_counter;
    logic       saved_rw;
    logic [6:0] saved_addr;
    logic [7:0] saved_data;
    
    // Clock divider for I2C clock generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_counter <= 8'd0;
            clk_pulse <= 1'b0;
        end else begin
            if (clk_counter >= CLK_DIV - 1) begin
                clk_counter <= 8'd0;
                clk_pulse <= 1'b1;
            end else begin
                clk_counter <= clk_counter + 1'b1;
                clk_pulse <= 1'b0;
            end
        end
    end
    
    // SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            I2C_SCL <= 1'b1;
        end else if (scl_enable) begin
            if (clk_counter < CLK_DIV_HALF)
                I2C_SCL <= 1'b0;
            else
                I2C_SCL <= 1'b1;
        end else begin
            I2C_SCL <= 1'b1;  // SCL high when idle
        end
    end
    
    // Bidirectional SDA handling
    assign I2C_SDA = sda_enable ? sda_out : 1'bz;
    
    // State machine - sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            shift_reg <= 8'd0;
            bit_counter <= 4'd0;
            data_out <= 8'd0;
            saved_rw <= 1'b0;
            saved_addr <= 7'd0;
            saved_data <= 8'd0;
        end else if (clk_pulse) begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    if (I2C_Start) begin
                        saved_addr <= slave_addr;
                        saved_rw <= RW;
                        saved_data <= data_in;
                    end
                end
                
                START: begin
                    shift_reg <= {saved_addr, saved_rw};
                    bit_counter <= 4'd8;
                end
                
                SEND_ADDR, SEND_DATA: begin
                    if (bit_counter > 0) begin
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        bit_counter <= bit_counter - 1'b1;
                    end
                end
                
                DATA_ACK: begin
                    if (saved_rw) begin  // Read operation
                        bit_counter <= 4'd8;
                    end else begin  // Write operation
                        shift_reg <= saved_data;
                        bit_counter <= 4'd8;
                    end
                end
                
                READ_DATA: begin
                    if (bit_counter > 0) begin
                        shift_reg <= {shift_reg[6:0], I2C_SDA};
                        bit_counter <= bit_counter - 1'b1;
                    end else begin
                        data_out <= shift_reg;
                    end
                end
            endcase
        end
    end
    
    // State machine - combinational logic
    always_comb begin
        // Default values
        next_state = state;
        sda_out = 1'b1;
        sda_enable = 1'b1;
        scl_enable = 1'b0;
        busy = 1'b1;
        I2C_En = 1'b1;
        
        case (state)
            IDLE: begin
                busy = 1'b0;
                I2C_En = 1'b0;
                if (I2C_Start) begin
                    next_state = START;
                end
            end
            
            START: begin
                // Generate start condition: SDA goes low while SCL is high
                sda_out = 1'b0;
                scl_enable = 1'b0;  // Keep SCL high
                next_state = SEND_ADDR;
            end
            
            SEND_ADDR: begin
                scl_enable = 1'b1;
                if (bit_counter > 0) begin
                    sda_out = shift_reg[7];
                end else begin
                    next_state = ADDR_ACK;
                end
            end
            
            ADDR_ACK: begin
                scl_enable = 1'b1;
                sda_enable = 1'b0;  // Release SDA for slave ACK
                if (!I2C_SDA) begin  // Check for ACK (SDA low)
                    next_state = DATA_ACK;
                end else begin
                    next_state = STOP;  // NACK received, abort
                end
            end
            
            DATA_ACK: begin
                scl_enable = 1'b1;
                if (saved_rw) begin  // Read operation
                    next_state = READ_DATA;
                end else begin  // Write operation
                    next_state = SEND_DATA;
                end
            end
            
            SEND_DATA: begin
                scl_enable = 1'b1;
                if (bit_counter > 0) begin
                    sda_out = shift_reg[7];
                end else begin
                    next_state = SEND_ACK;
                end
            end
            
            SEND_ACK: begin
                scl_enable = 1'b1;
                sda_enable = 1'b0;  // Release SDA for slave ACK
                next_state = STOP;
            end
            
            READ_DATA: begin
                scl_enable = 1'b1;
                sda_enable = 1'b0;  // Release SDA for reading
                if (bit_counter == 0) begin
                    next_state = SEND_NACK;
                end
            end
            
            SEND_NACK: begin
                scl_enable = 1'b1;
                sda_out = 1'b1;  // Send NACK (SDA high)
                next_state = STOP;
            end
            
            STOP: begin
                // Generate stop condition: SDA goes high while SCL is high
                scl_enable = 1'b0;  // SCL high
                sda_out = 1'b0;     // Keep SDA low initially
                next_state = STOP_WAIT;
            end
            
            STOP_WAIT: begin
                scl_enable = 1'b0;  // SCL high
                sda_out = 1'b1;     // Release SDA (goes high)
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule