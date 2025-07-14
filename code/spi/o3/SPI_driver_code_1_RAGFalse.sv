module SPI_driver(
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  data_in,
    input  logic        SPI_MISO,
    input  logic        SPI_start,
    output logic        SPI_MOSI,
    output logic        SPI_CLK,
    output logic        SPI_EN,      // Active–low chip-select
    output logic [7:0]  data_out
);

    // ------------------------------------------------------------
    // Parameters for CPOL/CPHA = 1/0  (SPI mode-2) and clock prescale
    // ------------------------------------------------------------
    localparam bit CPOL      = 1'b1;           // Clock idle high
    localparam bit CPHA      = 1'b0;           // Sample on leading edge
    parameter     int DIVIDE = 4;              // System-clk cycles per half-SCLK

    // ------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------
    typedef enum logic [1:0] {IDLE, LOAD, XFER, DONE} state_t;
    state_t state, next_state;

    // ------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------
    logic [$clog2(DIVIDE)-1:0] div_cnt;
    logic                      sclk_int;       // Internal SCLK
    logic [7:0]                shft_tx, shft_rx;
    logic [3:0]                bit_cnt;        // Counts 8 transfers

    // ------------------------------------------------------------
    // Sequential state register
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)
            IDLE : if (SPI_start)          next_state = LOAD;
            LOAD :                         next_state = XFER;
            XFER: if (bit_cnt == 0 && sclk_int == CPOL)
                                             next_state = DONE;
            DONE :                         next_state = IDLE;
        endcase
    end

    // ------------------------------------------------------------
    // Clock divider & SCLK generation (idle high)
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_cnt  <= '0;
            sclk_int <= CPOL;
        end
        else begin
            if (state == XFER) begin
                if (div_cnt == DIVIDE-1) begin
                    div_cnt  <= '0;
                    sclk_int <= ~sclk_int;          // Toggle SCLK
                end
                else
                    div_cnt <= div_cnt + 1;
            end
            else begin
                div_cnt  <= '0;
                sclk_int <= CPOL;                   // Hold idle
            end
        end
    end

    // ------------------------------------------------------------
    // Shift logic (CPOL=1, CPHA=0 : sample on falling, change on rising)
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            shft_tx  <= 8'h00;
            shft_rx  <= 8'h00;
            bit_cnt  <= 4'd0;
            SPI_MOSI <= 1'b0;
        end
        else begin
            case (state)
                LOAD: begin
                    shft_tx  <= data_in;
                    bit_cnt  <= 4'd8;
                    SPI_MOSI <= data_in[7];         // Present first bit
                end

                XFER: if (div_cnt == DIVIDE-1) begin
                    if (sclk_int == CPOL) begin     // Falling edge (leading)
                        shft_rx <= {shft_rx[6:0], SPI_MISO};
                    end
                    else begin                      // Rising edge (trailing)
                        shft_tx <= {shft_tx[6:0], 1'b0};
                        SPI_MOSI <= shft_tx[6];
                        bit_cnt  <= bit_cnt - 1;
                    end
                end

                default: ;
            endcase
        end
    end

    // ------------------------------------------------------------
    // Capture received byte
    // ------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            data_out <= 8'h00;
        else if (state == DONE)
            data_out <= shft_rx;
    end

    // ------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------
    assign SPI_CLK = sclk_int;
    assign SPI_EN  = (state == XFER) ? 1'b0 : 1'b1; // Active-low
endmodule