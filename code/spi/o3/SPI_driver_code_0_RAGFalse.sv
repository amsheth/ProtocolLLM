module SPI_driver
(
    input  logic        clk,        // System clock
    input  logic        rst,        // Active-high synchronous reset
    input  logic [7:0]  data_in,    // Parallel byte to transmit
    input  logic        SPI_MISO,   // Serial data from slave
    input  logic        SPI_start,  // Pulse = start a transaction

    output logic        SPI_MOSI,   // Serial data to slave
    output logic        SPI_CLK,    // SPI clock  (idle = 1)
    output logic        SPI_EN,     // Active-low chip-select
    output logic [7:0]  data_out    // Parallel byte received
);

    // ---------------------------------------------------------
    // User adjustable clock divider (system_clk -> spi_clk)
    // spi_freq = system_freq / (2*CLK_DIV)
    // ---------------------------------------------------------
    parameter int CLK_DIV = 4;            // must be ≥2 and even

    // ---------------------------------------------------------
    // Registers / wires
    // ---------------------------------------------------------
    logic [15:0] div_cnt;                 // generic large enough
    logic        spi_clk_int;             // internal SPI clock
    logic        spi_clk_prev;            // edge detector
    logic [2:0]  bit_cnt;
    logic [7:0]  shifter_tx;
    logic [7:0]  shifter_rx;
    logic        busy;

    //----------------------------------------------------------
    // Defaults
    //----------------------------------------------------------
    assign SPI_CLK = spi_clk_int;
    assign SPI_EN  = ~busy;               // active-low CS

    //----------------------------------------------------------
    // Clock-divider : generates MODE-3 clock (idle = 1)
    //----------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            div_cnt     <= '0;
            spi_clk_int <= 1'b1;          // CPOL = 1  (idle high)
        end
        else if (busy) begin
            if (div_cnt == (CLK_DIV-1)) begin
                div_cnt     <= '0;
                spi_clk_int <= ~spi_clk_int;  // toggle
            end
            else
                div_cnt <= div_cnt + 1;
        end
        else begin
            div_cnt     <= '0;
            spi_clk_int <= 1'b1;          // keep idle high
        end
    end

    //----------------------------------------------------------
    // Transaction control & data shift
    //----------------------------------------------------------
    always_ff @(posedge clk) begin
        spi_clk_prev <= spi_clk_int;      // store previous for edge detect

        if (rst) begin
            busy       <= 1'b0;
            SPI_MOSI   <= 1'b0;
            data_out   <= 8'h00;
            bit_cnt    <= 3'd0;
            shifter_tx <= 8'h00;
            shifter_rx <= 8'h00;
        end
        else begin
            //--------------------------------------------------
            // Start new transaction
            //--------------------------------------------------
            if (SPI_start && !busy) begin
                busy       <= 1'b1;
                shifter_tx <= data_in;
                shifter_rx <= 8'h00;
                bit_cnt    <= 3'd7;       // 8 bits -> 7 down to 0
            end

            //--------------------------------------------------
            // Active transaction  (MODE-3 timing)
            // • Falling edge : update MOSI, shift out next bit
            // • Rising  edge : sample MISO, shift into RX
            //--------------------------------------------------
            if (busy) begin
                // Detect falling edge (1 -> 0)
                if ( spi_clk_prev && !spi_clk_int ) begin
                    SPI_MOSI   <= shifter_tx[7];              // present next bit
                    shifter_tx <= {shifter_tx[6:0], 1'b0};    // shift left
                end

                // Detect rising edge (0 -> 1)
                if ( !spi_clk_prev && spi_clk_int ) begin
                    shifter_rx <= {shifter_rx[6:0], SPI_MISO}; // sample
                    if (bit_cnt == 0) begin
                        busy     <= 1'b0;                     // done
                        data_out <= {shifter_rx[6:0], SPI_MISO};
                    end
                    else
                        bit_cnt <= bit_cnt - 1;
                end
            end
        end
    end

endmodule