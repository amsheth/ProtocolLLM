module SPI_driver(input logic clk, input logic rst, input logic [7:0] data_in, input logic SPI_MISO, input logic SPI_start, output logic SPI_MOSI, output logic SPI_CLK, output logic SPI_EN, output logic [7:0] data_out);
  // CPOL = 0, CPHA = 1
  parameter CPOL = 0;
  parameter CPHA = 1;

  enum logic {IDLE, START, TRANSFER} state, next_state;
  logic [2:0] bit_cnt;
  logic [7:0] shift_reg;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= IDLE;
      bit_cnt <= 3'b0;
      shift_reg <= 8'h0;
    end else begin
      state <= next_state;
      case (next_state)
        TRANSFER: begin
          if (bit_cnt < 3'd7) begin
            bit_cnt <= bit_cnt + 1;
            shift_reg <= {shift_reg[6:0], SPI_MISO};
          end else begin
            data_out <= shift_reg;
            bit_cnt <= 3'b0;
          end
        end
      endcase
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: if (SPI_start) next_state = START;
      START: next_state = TRANSFER;
      TRANSFER: if (bit_cnt == 3'd7) next_state = IDLE;
    endcase
  end

  always_comb begin
    SPI_CLK = CPOL ? clk : ~clk;
    SPI_MOSI = shift_reg[7];
    case (CPHA)
      0: SPI_CLK = state == TRANSFER ? clk : ~clk;
      1: SPI_CLK = state == TRANSFER ? ~clk : clk;
    endcase
  end

  assign SPI_EN = (state != IDLE);
endmodule