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

  localparam CPOL = 1;
  localparam CPHA = 0;
  localparam BITS = 8;
  localparam CLK_DIV_MAX = 10;

  typedef enum logic [2:0] {
    IDLE,
    START_TX,
    DRIVE_MOSI_PRE,
    CLK_EDGE1,
    CLK_EDGE2,
    END_TX
  } spi_state_e;

  spi_state_e current_state, next_state;

  logic s_SPI_MOSI;
  logic s_SPI_CLK;
  logic s_SPI_EN;
  logic [7:0] s_data_out;

  logic [BITS-1:0] tx_data_reg;
  logic [BITS-1:0] rx_data_reg;
  logic [$clog2(BITS)-1:0] bit_counter;

  logic [$clog2(CLK_DIV_MAX)-1:0] clk_divider_counter;

  assign SPI_MOSI = s_SPI_MOSI;
  assign SPI_CLK  = s_SPI_CLK;
  assign SPI_EN   = s_SPI_EN;
  assign data_out = s_data_out;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      current_state <= IDLE;
      s_SPI_MOSI <= 1'b0;
      s_SPI_CLK <= CPOL;
      s_SPI_EN <= 1'b1;
      s_data_out <= 8'h00;
      tx_data_reg <= 8'h00;
      rx_data_reg <= 8'h00;
      bit_counter <= 0;
      clk_divider_counter <= 0;
    end else begin
      current_state <= next_state;

      s_SPI_MOSI <= s_SPI_MOSI;
      s_SPI_CLK <= s_SPI_CLK;
      s_SPI_EN <= s_SPI_EN;
      s_data_out <= s_data_out;
      tx_data_reg <= tx_data_reg;
      rx_data_reg <= rx_data_reg;
      bit_counter <= bit_counter;
      clk_divider_counter <= clk_divider_counter;

      case (current_state)
        IDLE: begin
          s_SPI_EN <= 1'b1;
          s_SPI_CLK <= CPOL;
          s_SPI_MOSI <= 1'b0;
          s_data_out <= 8'h00;
          clk_divider_counter <= 0;
          bit_counter <= 0;
          if (SPI_start) begin
            next_state <= START_TX;
          end else begin
            next_state <= IDLE;
          end
        end

        START_TX: begin
          s_SPI_EN <= 1'b0;
          tx_data_reg <= data_in;
          rx_data_reg <= 8'h00;
          bit_counter <= 0;
          clk_divider_counter <= 0;
          next_state <= DRIVE_MOSI_PRE;
        end

        DRIVE_MOSI_PRE: begin
          s_SPI_EN <= 1'b0;
          s_SPI_CLK <= CPOL;
          s_SPI_MOSI <= tx_data_reg[BITS-1 - bit_counter];

          if (clk_divider_counter == CLK_DIV_MAX - 1) begin
            clk_divider_counter <= 0;
            next_state <= CLK_EDGE1;
          end else begin
            clk_divider_counter <= clk_divider_counter + 1;
            next_state <= DRIVE_MOSI_PRE;
          end
        end

        CLK_EDGE1: begin
          s_SPI_EN <= 1'b0;
          s_SPI_CLK <= ~CPOL;

          if (clk_divider_counter == CLK_DIV_MAX - 1) begin
            rx_data_reg <= {rx_data_reg[BITS-2:0], SPI_MISO};
            clk_divider_counter <= 0;
            next_state <= CLK_EDGE2;
          end else begin
            clk_divider_counter <= clk_divider_counter + 1;
            next_state <= CLK_EDGE1;
          end
        end

        CLK_EDGE2: begin
          s_SPI_EN <= 1'b0;
          s_SPI_CLK <= CPOL;
          s_SPI_MOSI <= tx_data_reg[BITS-1 - bit_counter];

          if (clk_divider_counter == CLK_DIV_MAX - 1) begin
            tx_data_reg <= tx_data_reg << 1;
            bit_counter <= bit_counter + 1;
            clk_divider_counter <= 0;

            if (bit_counter == BITS - 1) begin
              next_state <= END_TX;
            end else begin
              next_state <= DRIVE_MOSI_PRE;
            end
          end else begin
            clk_divider_counter <= clk_divider_counter + 1;
            next_state <= CLK_EDGE2;
          end
        end

        END_TX: begin
          s_SPI_EN <= 1'b1;
          s_SPI_CLK <= CPOL;
          s_data_out <= rx_data_reg;
          next_state <= IDLE;
        end

        default: begin
          next_state <= IDLE;
        end
      endcase
    end
  end

endmodule