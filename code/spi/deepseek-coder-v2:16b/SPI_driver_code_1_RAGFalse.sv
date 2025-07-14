module SPI_driver(
    input logic clk,
    input logic rst,
    input logic [7:0] data_in,
    input logic SPI_MISO,
    Input logic SPI_start,
    output logic SPI_MOSI,
    output logic SPI_CLK,
    output logic SPI_EN,
    output logic [7:0] data_out
);

  // Clock polarity and phase settings
  parameter CPOL = 1;
  parameter CPHA = 0;

  // Internal signals
  enum logic [1:0] {IDLE, START, TRANSFER, STOP} state;
  logic [2:0] bit_cnt;
  logic [7:0] shift_reg;
  logic clk_div;
  logic [1:0] clk_phase;

  // Clock divider to generate SPI clock
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      clk_div <= CPOL;
    end else begin
      clk_div <= ~clk_div;
    end
  end

  // Phase control for data sampling and shifting
  always_ff @(posedge clk_div or posedge rst) begin
    if (rst) begin
      clk_phase <= 0;
    end else begin
      clk_phase <= clk_phase + 1;
    end
  end

  // State machine to control the SPI transaction
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      bit_cnt <= 0;
      shift_reg <= 0;
      SPI_CLK <= CPOL;
      SPI_MOSI <= 0;
      SPI_EN <= 0;
      data_out <= 0;
    end else begin
      case (state)
        IDLE: begin
          if (SPI_start) begin
            state <= START;
            bit_cnt <= 7;
            shift_reg <= data_in;
            SPI_EN <= 1;
          end
        end
        START: begin
          if (clk_phase == 0) begin
            SPI_CLK <= ~CPOL;
            SPI_MOSI <= shift_reg[7];
          end else begin
            state <= TRANSFER;
          end
        end
        TRANSFER: begin
          if (clk_phase == 1) begin
            SPI_CLK <= ~CPOL;
            shift_reg <= {shift_reg[6:0], SPI_MISO};
          end else if (clk_phase == 3) begin
            state <= STOP;
          end
        end
        STOP: begin
          if (clk_phase == 2) begin
            data_out <= shift_reg;
            SPI_EN <= 0;
            state <= IDLE;
          end
        end
      endcase
    end
  end
endmodule