module I2C_driver(
    input  logic       clk,         // System clock input
    input  logic       rst,         // Asynchronous reset input
    input  logic       I2C_Start,   // Initiate a transaction when high input
    input  logic       RW,          // Read/Write control: 0 for write, 1 for read input
    input  logic [6:0] slave_addr,  // 7-bit I2C slave address input
    input  logic [7:0] data_in,     // Data to be written (for write transactions)
    inout  logic       I2C_SDA,     // I2C data line (bidirectional)
    output logic       I2C_SCL,     // I2C clock line output
    output logic [7:0] data_out,    // Data received from slave (for read transactions)
    output logic       I2C_En,      // Module enable signal (active during transaction)
    output logic       busy         // Indicates the module is busy with a transaction
);

    // Parameters for clock divider and timing
    parameter CLK_FREQ = 50_000_000; // System clock frequency in Hz
    parameter I2C_FREQ = 100_000;   // Desired I2C frequency in Hz
    localparam CLK_DIV = CLK_FREQ / (I2C_FREQ * 4); // Clock divider factor

    // Internal signals
    logic [7:0] bit_cnt;
    logic [3:0] state, next_state;
    logic       scl_clk;
    logic       scl_clk_prev;
    logic       sda_out;
    logic       sda_in;
    logic       sda_dir;
    logic [7:0] data_reg;

    // Clock divider
    logic [$clog2(CLK_DIV):0] clk_div_cnt;
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            clk_div_cnt <= '0;
        else if (clk_div_cnt == CLK_DIV - 1)
            clk_div_cnt <= '0;
        else
            clk_div_cnt <= clk_div_cnt + 1'b1;
    end

    // Generate SCL clock signal
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            scl_clk <= 1'b1;
        else if (clk_div_cnt == CLK_DIV - 1)
            scl_clk <= ~scl_clk;
    end

    // State machine for I2C protocol
    typedef enum logic [3:0] {
        IDLE,
        START,
        ADDR,
        ACK_ADDR,
        WRITE_DATA,
        ACK_WRITE,
        READ_DATA,
        SEND_ACK,
        STOP
    } state_t;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // State transition logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (I2C_Start)
                    next_state = START;
            end
            START: begin
                if (!scl_clk && scl_clk_prev)
                    next_state = ADDR;
            end
            ADDR: begin
                if (bit_cnt == 8'b1000)
                    next_state = ACK_ADDR;
            end
            ACK_ADDR: begin
                if (!scl_clk && scl_clk_prev)
                    next_state = RW ? READ_DATA : WRITE_DATA;
            end
            WRITE_DATA: begin
                if (bit_cnt == 8'b1000)
                    next_state = ACK_WRITE;
            end
            ACK_WRITE: begin
                if (!scl_clk && scl_clk_prev)
                    next_state = I2C_Start ? WRITE_DATA : STOP;
            end
            READ_DATA: begin
                if (bit_cnt == 8'b1000)
                    next_state = SEND_ACK;
            end
            SEND_ACK: begin
                if (!scl_clk && scl_clk_prev)
                    next_state = I2C_Start ? READ_DATA : STOP;
            end
            STOP: begin
                if (!scl_clk && scl_clk_prev)
                    next_state = IDLE;
            end
        endcase
    end

    // Output logic and state actions
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt <= '0;
            data_reg <= '0;
            I2C_SCL <= 1'b1;
            sda_out <= 1'b1;
            sda_dir <= 1'b1;
            busy <= 1'b0;
            I2C_En <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    bit_cnt <= '0;
                    data_reg <= RW ? data_in : {slave_addr, RW};
                    sda_out <= 1'b1;
                    sda_dir <= 1'b1;
                    busy <= 1'b0;
                    I2C_En <= 1'b0;
                end
                START: begin
                    if (!scl_clk && scl_clk_prev) begin
                        sda_out <= 1'b0;
                        sda_dir <= 1'b1;
                        busy <= 1'b1;
                        I2C_En <= 1'b1;
                    end
                end
                ADDR, WRITE_DATA: begin
                    if (!scl_clk && scl_clk_prev) begin
                        sda_out <= data_reg[7];
                        sda_dir <= 1'b1;
                        data_reg <= {data_reg[6:0], 1'b0};
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end
                ACK_ADDR, ACK_WRITE, SEND_ACK: begin
                    if (!scl_clk && scl_clk_prev) begin
                        sda_dir <= 1'b0;
                        bit_cnt <= '0;
                    end
                end
                READ_DATA: begin
                    if (scl_clk && !scl_clk_prev)
                        data_reg <= {data_reg[6:0], sda_in};
                    else if (!scl_clk && scl_clk_prev) begin
                        bit_cnt <= bit_cnt + 1'b1;
                        if (bit_cnt == 8'b1000) begin
                            data_out <= data_reg;
                            sda_out <= RW ? 1'b0 : 1'b1; // Send ACK/NACK
                            sda_dir <= 1'b1;
                        end
                    end
                end
                STOP: begin
                    if (!scl_clk && scl_clk_prev) begin
                        sda_out <= 1'b0;
                        sda_dir <= 1'b1;
                    end else if (scl_clk && !scl_clk_prev) begin
                        sda_out <= 1'b1;
                        sda_dir <= 1'b1;
                    end
                end
            endcase
        end
    end

    // SDA tristate buffer
    assign I2C_SDA = sda_dir ? sda_out : 1'bz;
    assign sda_in = I2C_SDA;

    // Previous SCL clock signal for edge detection
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            scl_clk_prev <= 1'b0;
        else
            scl_clk_prev <= scl_clk;
    end

endmodule