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

    // Parameters
    parameter CLK_FREQ = 50_000_000; // System clock frequency in Hz
    parameter I2C_FREQ = 100_000;     // Desired I2C frequency in Hz
    parameter CLK_DIV = CLK_FREQ / (5 * I2C_FREQ) - 1; // Clock divider value

    // Internal signals
    logic [15:0] clk_div_cnt; // Clock divider counter
    logic        scl;           // Internal SCL signal
    logic        scl_en;        // SCL enable signal
    logic        sda;           // Internal SDA signal
    logic        sda_en;        // SDA enable signal
    logic [3:0]  bit_cnt;       // Bit counter for byte transfers
    logic [7:0]  byte_reg;      // Byte register for data transfer
    logic [2:0]  state;         // State machine state
    logic        start_sent;    // Start condition sent flag
    logic        stop_sent;     // Stop condition sent flag
    logic        ack_received;  // Acknowledge received flag
    logic        read_done;     // Read operation done flag

    // State definitions
    localparam IDLE = 3'b000;
    localparam START = 3'b001;
    localparam ADDR = 3'b010;
    localparam DATA = 3'b011;
    localparam STOP = 3'b100;

    // Clock divider
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            clk_div_cnt <= '0;
            scl <= 1'b1;
        end else if (scl_en) begin
            if (clk_div_cnt == CLK_DIV) begin
                clk_div_cnt <= '0;
                scl <= ~scl;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1;
            end
        end
    end

    // SDA and SCL output assignments
    assign I2C_SCL = scl;
    assign I2C_SDA = sda_en ? sda : 1'bz;

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 1'b0;
            I2C_En <= 1'b0;
            start_sent <= 1'b0;
            stop_sent <= 1'b0;
            ack_received <= 1'b0;
            read_done <= 1'b0;
            bit_cnt <= 4'b0000;
            byte_reg <= 8'b00000000;
        end else begin
            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                    if (I2C_Start) begin
                        state <= START;
                        busy <= 1'b1;
                        I2C_En <= 1'b1;
                        start_sent <= 1'b0;
                        stop_sent <= 1'b0;
                        ack_received <= 1'b0;
                        read_done <= 1'b0;
                        bit_cnt <= 4'b0000;
                        byte_reg <= {slave_addr, RW};
                    end
                end
                START: begin
                    if (!start_sent) begin
                        scl_en <= 1'b1;
                        sda_en <= 1'b1;
                        sda <= 1'b0; // Pull SDA low to generate start condition
                        start_sent <= 1'b1;
                    end else if (scl) begin
                        state <= ADDR;
                        scl_en <= 1'b0;
                        sda_en <= 1'b0;
                    end
                end
                ADDR: begin
                    if (bit_cnt < 8) begin
                        if (scl) begin
                            sda_en <= 1'b1;
                            sda <= byte_reg[7];
                            byte_reg <= {1'b0, byte_reg[7:1]};
                            bit_cnt <= bit_cnt + 1;
                        end
                    end else begin
                        if (scl) begin
                            sda_en <= 1'b0; // Release SDA for ACK/NACK
                            bit_cnt <= 4'b0000;
                            state <= DATA;
                        end
                    end
                end
                DATA: begin
                    if (RW == 1'b0) begin // Write operation
                        if (bit_cnt < 8) begin
                            if (scl) begin
                                sda_en <= 1'b1;
                                sda <= data_in[7];
                                data_in <= {1'b0, data_in[7:1]};
                                bit_cnt <= bit_cnt + 1;
                            end
                        end else begin
                            if (scl) begin
                                sda_en <= 1'b0; // Release SDA for ACK/NACK
                                bit_cnt <= 4'b0000;
                                state <= STOP;
                            end
                        end
                    end else begin // Read operation
                        if (bit_cnt < 8) begin
                            if (scl) begin
                                data_out[7] <= I2C_SDA;
                                data_out <= {data_out[6:0], 1'b0};
                                bit_cnt <= bit_cnt + 1;
                            end
                        end else begin
                            if (scl) begin
                                sda_en <= 1'b1;
                                sda <= 1'b0; // Send ACK
                                bit_cnt <= 4'b0000;
                                state <= STOP;
                                read_done <= 1'b1;
                            end
                        end
                    end
                end
                STOP: begin
                    if (!stop_sent) begin
                        scl_en <= 1'b1;
                        sda_en <= 1'b1;
                        sda <= 1'b0; // Pull SDA low
                        stop_sent <= 1'b1;
                    end else if (scl) begin
                        sda <= 1'b1; // Release SDA to generate stop condition
                        scl_en <= 1'b0;
                        sda_en <= 1'b0;
                        state <= IDLE;
                        busy <= 1'b0;
                        I2C_En <= 1'b0;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule