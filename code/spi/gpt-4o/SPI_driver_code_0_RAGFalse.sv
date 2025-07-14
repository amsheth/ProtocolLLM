module SPI_driver(
    input logic clk,
    input logic rst,
    input logic [7:0] data_in,
    input logic SPI_MISO,
    input logic SPI_start,
    output logic SPI_MOSI,
    output logic SPI_CLK,
    output logic SPI_EN,
    output logic [7:0] data_out
);

    // State encoding
    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        START   = 2'b01,
        TRANSFER= 2'b10,
        DONE    = 2'b11
    } state_t;

    state_t current_state, next_state;

    // Register to hold data and counter
    logic [7:0] shift_register;
    logic [2:0] bit_counter;

    // Generate SPI clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_CLK <= 1'b1; // CPOL = 1; Base level high
        end else if (current_state == TRANSFER) begin
            SPI_CLK <= ~SPI_CLK; // Toggle clock for each cycle
        end else begin
            SPI_CLK <= 1'b1;
        end
    end

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
                if (SPI_start) begin
                    next_state = START;
                end
            end
            START: begin
                next_state = TRANSFER;
            end
            TRANSFER: begin
                if (bit_counter == 3'b111) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    // Output and counter logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_MOSI <= 1'b0;
            SPI_EN <= 1'b0;
            bit_counter <= 3'b0;
            shift_register <= 8'b0;
            data_out <= 8'b0;
        end else begin
            case (current_state)
                IDLE: begin
                    SPI_EN <= 1'b0;
                end
                START: begin
                    SPI_EN <= 1'b1;
                    shift_register <= data_in;
                    bit_counter <= 3'b0;
                end
                TRANSFER: begin
                    if (SPI_CLK == 1'b1) begin
                        SPI_MOSI <= shift_register[7];
                    end else begin
                        shift_register <= {shift_register[6:0], SPI_MISO};
                        bit_counter <= bit_counter + 1'b1;
                    end
                end
                DONE: begin
                    SPI_EN <= 1'b0;
                    data_out <= shift_register;
                end
            endcase
        end
    end

endmodule