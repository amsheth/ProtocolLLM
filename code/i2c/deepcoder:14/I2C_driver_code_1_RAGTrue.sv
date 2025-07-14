module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
    input  logic       I2C_Start,   // Initiate a transaction when high input
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read input
    input  logic [9:0] slave_addr,  // 10-bit I2C slave address input
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

// Define states
typedef enum {
    IDLE,
    START,
    ADDR,
    DATA,
    STOP
} state_t;

state_t state = IDLE;

// Internal signals
logic [7:0] data_tx;  // Data to transmit
logic [7:0] data_rx;  // Data to receive
logic sda;             // SDA signal
logic scl;             // SCL signal
logic enable;           // Module enable
logic [7:0] rx_data;   // Received data

// Clock divider for I2C SCL
logic [15:0]clk_div_cnt; // Clock divider counter
logic       scl_en;      // SCL enable signal

// Generate SCL clock
always_ff @ (posedge clk) begin
    if (rst) begin
        scl_en <= 0;
        clk_div_cnt <= 0;
    end else begin
        if (scl_en) begin
            if (clk_div_cnt == 16'd5) begin
                scl_en <= 0;
                clk_div_cnt <= 0;
            end else begin
                scl_en <= 1;
                clk_div_cnt <= clk_div_cnt + 1;
            end
        end else begin
            if (clk_div_cnt == 16'd10) begin
                scl_en <= 1;
                clk_div_cnt <= 0;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1;
            end
        end
    end
end

// Assign SCL
assign I2C_SCL = scl_en;

// State machine
always_ff @ (posedge clk) begin
    if (rst) begin
        state <= IDLE;
        data_tx <= 0;
        data_rx <= 0;
        I2C_SDA <= 1;  // SDA high during idle
        enable <= 0;
        busy <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (I2C_Start) begin
                    state <= START;
                    I2C_SDA <= 1;
                    enable <= 1;
                    busy <= 1;
                end
            end

            START: begin
                // Generate start condition (SCL high, SDA from high to low)
                I2C_SDA <= 0;
                if (!I2C_SDA) begin
                    state <= ADDR;
                end
            end

            ADDR: begin
                // Send address
                I2C_SDA <= ( slave_addr[8:0] >> (9 - addr_bit)) & 1;
                if (addr_bit == 9) begin
                    state <= DATA;
                end
            end

            DATA: begin
                // Send or receive data
                if (RW == 0) begin
                    // Writing
                    I2C_SDA <= data_in[7 - data_bit];
                    if (data_bit == 7) begin
                        state <= STOP;
                    end
                end else begin
                    // Reading
                    data_out[7 - data_bit] <= I2C_SDA;
                    if (data_bit == 7) begin
                        state <= STOP;
                    end
                end
            end

            STOP: begin
                // Generate stop condition (SCL high, SDA from low to high)
                I2C_SDA <= 1;
                if (I2C_SDA == 1) begin
                    state <= IDLE;
                    enable <= 0;
                    busy <= 0;
                end
            end
        endcase
    end
end

// Address and data counters
integer addr_bit = 0;
integer data_bit = 0;

always_ff @ (posedge I2C_SCL) begin
    if (rst) begin
        addr_bit <= 0;
        data_bit <= 0;
    end else begin
        case (state)
            ADDR: begin
                addr_bit <= addr_bit + 1;
            end

            DATA: begin
                data_bit <= data_bit + 1;
            end
        endcase
    end
end

// Assign SDA and SCL
assign I2C_SDA = (enable) ? sda : 'Z; // Tri-state when not enabled
assign I2C_SCL = scl;

// Additional logic for acknowledgment handling and proper data transfer
// ... (Implement as per I2C protocol)

// For simplicity, this example assumes perfect acknowledgment (ACK) from the slave.
// In a complete implementation, the receiving side would capture the ACK/NACK.

endmodule