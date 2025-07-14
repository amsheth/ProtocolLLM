module SPI_driver
(
    input  logic       clk,        // system clock
    input  logic       rst,        // asynchronous reset, active-high
    input  logic [7:0] data_in,    // byte to transmit
    input  logic       SPI_MISO,   // data from slave
    input  logic       SPI_start,  // start pulse (one clk cycle)
    output logic       SPI_MOSI,   // data to slave
    output logic       SPI_CLK,    // generated SCK
    output logic       SPI_EN,     // chip–select (active-low)
    output logic [7:0] data_out    // byte received
);

    //---------------------------------------------------------------------
    // USER PARAMETER:  divide system clock to obtain SCK
    //  (SPI_CLK  =  clk / (2*CLK_DIV)  ;  CLK_DIV must be ≥2 and even)
    //---------------------------------------------------------------------
    parameter int unsigned CLK_DIV = 4;

    //---------------------------------------------------------------------
    // Internal signals / registers
    //---------------------------------------------------------------------
    typedef enum logic [1:0] {IDLE, LOAD, TRANSFER, DONE} state_t;

    state_t                state, next_state;

    logic [$clog2(CLK_DIV)-1:0] div_cnt;   // clock-divider counter
    logic                        sclk;     // generated SPI clock (CPOL=0)
    logic                        sclk_prev; // for edge detection

    logic [7:0] tx_shift;   // shift-register for MOSI
    logic [7:0] rx_shift;   // shift-register for MISO
    logic [2:0] bit_cnt;    // counts 7 … 0 (MSB first)

    //---------------------------------------------------------------------
    // Output assignments
    //---------------------------------------------------------------------
    assign SPI_CLK = (state == TRANSFER) ? sclk : 1'b0;          // CPOL = 0
    assign SPI_EN  = (state == TRANSFER || state == LOAD) ? 1'b0 // active-low
                                                          : 1'b1;
    assign SPI_MOSI = tx_shift[7];  // always drive MSB of TX shift-register
    assign data_out = rx_shift;     // valid after DONE state

    //---------------------------------------------------------------------
    // Clock-divider : generates “sclk” while in TRANSFER state
    //---------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            div_cnt <= '0;
            sclk    <= 1'b0;
        end
        else if (state == TRANSFER) begin
            if (div_cnt == CLK_DIV-1) begin
                div_cnt <= '0;
                sclk    <= ~sclk;         // toggle SCK
            end
            else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end
        else begin                       // keep SCK low when idle
            div_cnt <= '0;
            sclk    <= 1'b0;
        end
    end

    //---------------------------------------------------------------------
    // Main state-machine + shift logic  (Mode-1 : CPOL=0, CPHA=1)
    //
    //   • MOSI changes on leading edge  (rising, since CPOL=0)
    //   • MISO is sampled on trailing edge (falling)
    //---------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            tx_shift  <= '0;
            rx_shift  <= '0;
            bit_cnt   <= '0;
            sclk_prev <= 1'b0;
        end
        else begin
            sclk_prev <= sclk;        // store previous SCK for edge detection
            state     <= next_state;  // update state

            //-----------------------------------------------------------------
            // Actions inside TRANSFER state (edge-dependent)
            //-----------------------------------------------------------------
            if (state == TRANSFER) begin

                // Leading edge (rising) : place next data bit on MOSI
                if (!sclk_prev &&  sclk) begin          // rising edge
                    if (bit_cnt != 3'd0)
                        tx_shift <= {tx_shift[6:0], 1'b0}; // left-shift
                end

                // Trailing edge (falling) : sample MISO
                if ( sclk_prev && !sclk) begin          // falling edge
                    rx_shift[bit_cnt] <= SPI_MISO;       // store in correct bit
                    if (bit_cnt == 3'd0)
                        bit_cnt <= bit_cnt;              // stay at 0 (done)
                    else
                        bit_cnt <= bit_cnt - 1'b1;
                end
            end
        end
    end

    //---------------------------------------------------------------------
    // Next-state logic (combinational)
    //---------------------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)
            IDLE : if (SPI_start)      next_state = LOAD;
            LOAD :                     next_state = TRANSFER;
            TRANSFER : if (sclk_prev && !sclk && bit_cnt == 3'd0)
                                         next_state = DONE;  // after last sample
            DONE :                     next_state = IDLE;
            default:                   next_state = IDLE;
        endcase
    end

    //---------------------------------------------------------------------
    // State-entry actions that need one exact cycle
    //---------------------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // nothing extra
        end
        else begin
            if (state == LOAD && next_state == TRANSFER) begin
                tx_shift <= data_in;   // load byte to transmit
                bit_cnt  <= 3'd7;      // MSB first
            end
        end
    end

endmodule