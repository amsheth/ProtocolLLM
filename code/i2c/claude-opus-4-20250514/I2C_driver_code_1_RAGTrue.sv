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

    // Clock divider parameters (adjust based on system clock frequency)
    parameter CLK_DIV = 100;  // Divide system clock by 100 for I2C SCL
    
    // State machine states
    typedef enum logic [3:0] {
        IDLE,
        START,
        SEND_ADDR_HIGH,
        SEND_ADDR_LOW,
        CHECK_ACK1,
        WRITE_DATA,
        READ_DATA,
        CHECK_ACK2,
        SEND_ACK,
        STOP
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [7:0]  clk_div_counter;
    logic        scl_enable;
    logic        scl_clk;
    logic [3:0]  bit_counter;
    logic [9:0]  addr_reg;
    logic [7:0]  data_reg;
    logic        sda_out;
    logic        sda_oe;  // SDA output enable
    logic        ack_received;
    
    // Clock divider for SCL generation
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_counter <= 8'd0;
            scl_clk <= 1'b1;
        end else if (scl_enable) begin
            if (clk_div_counter == CLK_DIV - 1) begin
                clk_div_counter <= 8'd0;
                scl_clk <= ~scl_clk;
            end else begin
                clk_div_counter <= clk_div_counter + 1'b1;
            end
        end else begin
            clk_div_counter <= 8'd0;
            scl_clk <= 1'b1;
        end
    end
    
    // SCL generation with proper timing
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            I2C_SCL <= 1'b1;
        end else begin
            case (current_state)
                IDLE: I2C_SCL <= 1'b1;
                START: I2C_SCL <= (clk_div_counter < CLK_DIV/2) ? 1'b1 : scl_clk;
                STOP: I2C_SCL <= (clk_div_counter < CLK_DIV/2) ? 1'b0 : 1'b1;
                default: I2C_SCL <= scl_clk;
            endcase
        end
    end
    
    // Bidirectional SDA handling
    assign I2C_SDA = sda_oe ? sda_out : 1'bz;
    
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
                if (clk_div_counter == CLK_DIV - 1 && scl_clk) begin
                    next_state = SEND_ADDR_HIGH;
                end
            end
            
            SEND_ADDR_HIGH: begin
                if (bit_counter == 4'd2 && clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                    next_state = SEND_ADDR_LOW;
                end
            end
            
            SEND_ADDR_LOW: begin
                if (bit_counter == 4'd8 && clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                    next_state = CHECK_ACK1;
                end
            end
            
            CHECK_ACK1: begin
                if (clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                    if (!ack_received) begin
                        next_state = STOP;  // NACK received, abort
                    end else if (RW) begin
                        next_state = READ_DATA;
                    end else begin
                        next_state = WRITE_DATA;
                    end
                end
            end
            
            WRITE_DATA: begin
                if (bit_counter == 4'd8 && clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                    next_state = CHECK_ACK2;
                end
            end
            
            READ_DATA: begin
                if (bit_counter == 4'd8 && clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                    next_state = SEND_ACK;
                end
            end
            
            CHECK_ACK2, SEND_ACK: begin
                if (clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                    next_state = STOP;
                end
            end
            
            STOP: begin
                if (clk_div_counter == CLK_DIV - 1) begin
                    next_state = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Data path and control logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_counter <= 4'd0;
            addr_reg <= 10'd0;
            data_reg <= 8'd0;
            data_out <= 8'd0;
            sda_out <= 1'b1;
            sda_oe <= 1'b1;
            scl_enable <= 1'b0;
            busy <= 1'b0;
            I2C_En <= 1'b0;
            ack_received <= 1'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    bit_counter <= 4'd0;
                    sda_out <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_enable <= 1'b0;
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                    if (I2C_Start) begin
                        addr_reg <= slave_addr;
                        data_reg <= data_in;
                        busy <= 1'b1;
                        I2C_En <= 1'b1;
                    end
                end
                
                START: begin
                    scl_enable <= 1'b1;
                    // Generate start condition: SDA high to low while SCL high
                    if (clk_div_counter < CLK_DIV/2) begin
                        sda_out <= 1'b1;
                    end else begin
                        sda_out <= 1'b0;
                    end
                    bit_counter <= 4'd0;
                end
                
                SEND_ADDR_HIGH: begin
                    // Send high bits of 10-bit address (11110 + first 2 bits)
                    if (clk_div_counter == 0 && scl_clk) begin
                        case (bit_counter)
                            4'd0: sda_out <= 1'b1;  // 11110xx0 format
                            4'd1: sda_out <= 1'b1;
                            4'd2: sda_out <= 1'b1;
                            4'd3: sda_out <= 1'b1;
                            4'd4: sda_out <= 1'b0;
                            4'd5: sda_out <= addr_reg[9];
                            4'd6: sda_out <= addr_reg[8];
                            4'd7: sda_out <= 1'b0;  // Write bit for address
                        endcase
                    end
                    if (clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
                
                SEND_ADDR_LOW: begin
                    // Send low 8 bits of address
                    if (clk_div_counter == 0 && scl_clk) begin
                        sda_out <= addr_reg[7 - bit_counter];
                    end
                    if (clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
                
                CHECK_ACK1, CHECK_ACK2: begin
                    sda_oe <= 1'b0;  // Release SDA for slave ACK
                    if (clk_div_counter == CLK_DIV/2 && scl_clk) begin
                        ack_received <= !I2C_SDA;  // ACK is low
                    end
                    bit_counter <= 4'd0;
                end
                
                WRITE_DATA: begin
                    sda_oe <= 1'b1;
                    if (clk_div_counter == 0 && scl_clk) begin
                        sda_out <= data_reg[7 - bit_counter];
                    end
                    if (clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
                
                READ_DATA: begin
                    sda_oe <= 1'b0;  // Release SDA for slave to drive
                    if (clk_div_counter == CLK_DIV/2 && scl_clk) begin
                        data_out[7 - bit_counter] <= I2C_SDA;
                    end
                    if (clk_div_counter == CLK_DIV - 1 && !scl_clk) begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
                
                SEND_ACK: begin
                    sda_oe <= 1'b1;
                    sda_out <= 1'b1;  // Send NACK (high) to indicate end of read
                end
                
                STOP: begin
                    sda_oe <= 1'b1;
                    // Generate stop condition: SDA low to high while SCL high
                    if (clk_div_counter < CLK_DIV/2) begin
                        sda_out <= 1'b0;
                    end else begin
                        sda_out <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule