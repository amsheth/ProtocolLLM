module I2C_driver(
    input  logic        clk,        // System clock
    input  logic        rst,        // Asynchronous reset
    input  logic        I2C_Start,  // Initiate a transaction when high
    input  logic        RW,         // Read/Write control: 0 for write, 1 for read
    input  logic [6:0]  slave_addr, // 7-bit I2C slave address
    input  logic [7:0]  data_in,    // Data to be written (for write transactions)
    inout  logic        I2C_SDA,    // I2C data line (bidirectional)
    output logic        I2C_SCL,    // I2C clock line
    output logic [7:0]  data_out,   // Data received from slave (for read transactions)
    output logic        I2C_En,     // Module enable signal (active during transaction)
    output logic        busy        // Indicates the module is busy with a transaction
);

    typedef enum logic [2:0] {
        IDLE,
        START_CONDITION,
        SEND_ADDRESS,
        DATA_TRANSFER,
        STOP_CONDITION
    } state_t;

    state_t state, next_state;
    logic [3:0] bit_count;
    logic [7:0] byte_buffer;
    logic scl_enable, sda_drive, sda_data, ack_check;
    
    assign I2C_En = (state != IDLE);
    assign busy = I2C_En;

    // Clock divider for I2C_SCL generation
    logic [15:0] clk_div_counter;
    logic scl_clock;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_counter <= 16'b0;
            scl_clock <= 1'b1;
        end else begin
            if (clk_div_counter >= 'd249) begin // Assume clock is 100 MHz, generate 400 kHz SCL
                clk_div_counter <= 16'b0;
                scl_clock <= ~scl_clock;
            end else begin
                clk_div_counter <= clk_div_counter + 1'b1;
            end
        end
    end

    // I2C state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            bit_count <= 4'b0;
            byte_buffer <= 8'b0;
            I2C_SCL <= 1'b1;
            ack_check <= 1'b0;
        end else if (scl_clock) begin
            state <= next_state;
            if (sda_drive) begin
                I2C_SDA <= sda_data;
            end
            if (scl_enable) begin
                I2C_SCL <= ~I2C_SCL;
            end
        end
    end

    always_comb begin
        next_state = state;
        scl_enable = 1'b0;
        sda_drive = 1'b0;
        sda_data = 1'b1; // Default un-driven high
        ack_check = 1'b0;
        data_out = 8'b0;
        case (state)
            IDLE: begin
                if (I2C_Start) begin
                    next_state = START_CONDITION;
                    byte_buffer = {slave_addr, RW}; // Place address and RW bit in buffer
                    bit_count = 4'd8;
                end
            end
            
            START_CONDITION: begin
                // Start condition: SDA low while SCL high
                sda_drive = 1'b1;
                sda_data = 1'b0;
                scl_enable = 1'b1;

                if (!I2C_SCL) begin
                    next_state = SEND_ADDRESS;
                end
            end

            SEND_ADDRESS: begin
                // Send Address with R/W bit
                scl_enable = 1'b1;
                sda_drive = 1'b1;
                sda_data = byte_buffer[7];
                
                if (!I2C_SCL) begin
                    byte_buffer = {byte_buffer[6:0], 1'b0}; // Shift out data
                    bit_count = bit_count - 1;
                    if (bit_count == 0) begin
                        next_state = DATA_TRANSFER;
                        bit_count = 4'd8;  // Reset bit count for data phase
                        ack_check = 1'b1;  // Check for ACK bit
                    end
                end
            end

            DATA_TRANSFER: begin
                // Perform data read or write
                if (RW) begin
                    // Implement read logic here
                end else begin
                    // Implement write logic here
                end
                
                if (ack_check) begin
                    // Acknowledge handling
                end
            end

            STOP_CONDITION: begin
                // Generate Stop condition
                sda_drive = 1'b1;
                scl_enable = 1'b1;

                if (I2C_SCL) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
endmodule