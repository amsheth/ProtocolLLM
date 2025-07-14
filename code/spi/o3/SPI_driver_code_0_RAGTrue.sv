//-----------------------------------------------------------
//  Simple SPI MASTER (MODE-3 : CPOL = 1 , CPHA = 1)
//-----------------------------------------------------------
//  • Full-duplex, 8-bit transfer
//  • Generates the SPI clock from system clock (clk)
//  • Active-low chip–select  (SPI_EN)
//  • Data are driven on the falling edge and sampled on the
//    rising edge of SPI_CLK (MODE-3 requirements)
//-----------------------------------------------------------
module SPI_driver #(
    // Number of system-clock cycles that make ½ period of SPI_CLK
    //   SPI_CLK = clk / (2*DIVIDER)
    parameter int unsigned DIVIDER = 4        // even, ≥2
)(
    input  logic        clk ,       // system clock
    input  logic        rst ,       // synchronous reset (active high)

    // User interface
    input  logic  [7:0] data_in ,   // byte to send
    input  logic        SPI_start , // pulse => start new transfer
    output logic [7:0]  data_out ,  // byte just received
    // SPI lines
    input  logic        SPI_MISO ,  // Master-In  Slave-Out
    output logic        SPI_MOSI ,  // Master-Out Slave-In
    output logic        SPI_CLK ,   // Serial clock  (idle = ‘1’)
    output logic        SPI_EN      // Active-low chip select
);

   //--------------------------------------------------------
   //  Internal signals / registers
   //--------------------------------------------------------
   typedef enum logic [1:0] {IDLE, TRANSFER} state_t;
   state_t              state , state_n;

   logic [$clog2(DIVIDER)-1:0] div_cnt;     // clock divider counter
   logic                       sclk_reg;    // generated serial clock
   logic                       sclk_next;
   logic                       sclk_fall;   // 1 clk-tick wide
   logic                       sclk_rise;   // 1 clk-tick wide

   logic [7:0] tx_shift, rx_shift;
   logic [3:0] bit_cnt;                     // counts remaining bits

   //--------------------------------------------------------
   //  Clock divider / SCLK generator
   //--------------------------------------------------------
   always_ff @(posedge clk) begin
      if (rst) begin
         div_cnt  <= '0;
         sclk_reg <= 1'b1;                  // CPOL = 1  (idle high)
      end
      else begin
         if (state == TRANSFER) begin
            if (div_cnt == DIVIDER-1) begin
               div_cnt  <= '0;
               sclk_reg <= ~sclk_reg;       // toggle SCLK
            end else
               div_cnt <= div_cnt + 1;
         end
         else begin                         // IDLE
            div_cnt  <= '0;
            sclk_reg <= 1'b1;               // keep high while idle
         end
      end
   end

   // Edge detectors (one-cycle pulses in clk domain)
   logic sclk_reg_d;
   always_ff @(posedge clk) sclk_reg_d <= sclk_reg;
   assign sclk_rise = ( sclk_reg & ~sclk_reg_d);  // 0→1 in MODE-3
   assign sclk_fall = (~sclk_reg &  sclk_reg_d);  // 1→0

   //--------------------------------------------------------
   //  Main control FSM
   //--------------------------------------------------------
   always_ff @(posedge clk) begin
      if (rst) begin
         state   <= IDLE;
         bit_cnt <= '0;
         tx_shift<= '0;
         rx_shift<= '0;
      end
      else begin
         state <= state_n;

         //------- ACTIONS IN TRANSFER STATE ----------------
         if (state == TRANSFER) begin
            // Drive next bit on falling edge
            if (sclk_fall) begin
               {tx_shift, SPI_MOSI} <= {tx_shift[6:0], 1'b0}; // shift left
               bit_cnt <= bit_cnt - 1;
            end

            // Sample MISO on rising edge
            if (sclk_rise) begin
               rx_shift <= {rx_shift[6:0], SPI_MISO};
            end
         end
      end
   end

   // Next-state logic
   always_comb begin
      state_n = state;
      case (state)
         IDLE : begin
            if (SPI_start) begin
               state_n  = TRANSFER;
            end
         end

         TRANSFER : begin
            if ((bit_cnt == 4'd0) && sclk_rise) begin
               state_n = IDLE;              // finished after last sample
            end
         end
      endcase
   end

   //--------------------------------------------------------
   //  Outputs and miscellaneous synchronous assignments
   //--------------------------------------------------------
   always_ff @(posedge clk) begin
      if (rst) begin
         SPI_MOSI <= 1'b0;
         SPI_EN   <= 1'b1;                  // inactive (chip not selected)
         data_out <= 8'h00;
      end
      else begin
         // Load registers at start of a transfer
         if (state == IDLE && state_n == TRANSFER) begin
            tx_shift <= data_in;
            SPI_MOSI<= data_in[7];          // first bit put on MOSI after CS
            rx_shift<= '0;
            bit_cnt <= 4'd8;
            SPI_EN  <= 1'b0;                // assert CS (active-low)
         end
         // De-assert CS at the very end of the transfer
         else if (state == TRANSFER && state_n == IDLE) begin
            SPI_EN   <= 1'b1;
            data_out <= rx_shift;           // make received byte available
         end
      end
   end

   // Assign generated clock
   assign SPI_CLK = sclk_reg;

endmodule