module I2C_driver(
  input logic clk, rst, I2C_Start, RW, slave_addr[6:0], data_in[7:0],
  inout wire I2C_SDA, I2C_SCL,
  output logic busy, data_out[7:0]
);

// Internal variables
logic [15:0] counter; // Counter for clock divider
logic [7:0] shift_reg; // Shift register for data transfer
logic start_cond, stop_cond, ack_nack; // Start/stop conditions and ACK/NACK

// State machine states
enum {IDLE, START, ADDR_PHASE, DATA_PHASE, ACK_PHASE} state;

always @(posedge clk or negedge rst) begin
  if (!rst) begin // Asynchronous reset
    state <= IDLE;
    counter <= '0;
    shift_reg <= '0;
    start_cond <= '0;
    stop_cond <= '0;
    ack_nack <= '0;
  end else begin
    case (state)
      IDLE: begin
        if (I2C_Start) begin // Start condition
          state <= START;
          counter <= 16'h0000;
          shift_reg <= {slave_addr, RW};
          start_cond <= '1;
          stop_cond <= '0;
        end
      end
      START: begin
        if (counter == 16'h0000) begin // Clock divider is complete
          state <= ADDR_PHASE;
          counter <= 16'h0001;
          shift_reg <= {slave_addr, RW};
          start_cond <= '0;
          stop_cond <= '0;
        end else begin
          counter <= counter + 16'h0001;
        end
      end
      ADDR_PHASE: begin
        if (counter == 16'h0008) begin // 7-bit address and R/W bit transfer is complete
          state <= DATA_PHASE;
          counter <= 16'h0009;
          shift_reg <= '0;
          start_cond <= '0;
          stop_cond <= '0;
        end else begin
          counter <= counter + 16'h0001;
        end
      end
      DATA_PHASE: begin
        if (RW) begin // Read operation
          if (counter == 16'h0008) begin // Data transfer is complete
            state <= ACK_PHASE;
            counter <= 16'h0009;
            shift_reg <= '0;
            start_cond <= '0;
            stop_cond <= '0;
          end else begin
            counter <= counter + 16'h0001;
          end
        end else begin // Write operation
          if (counter == 16'h0008) begin // Data transfer is complete
            state <= ACK_PHASE;
            counter <= 16'h0009;
            shift_reg <= '0;
            start_cond <= '0;
            stop_cond <= '0;
          end else begin
            counter <= counter + 16'h0001;
          end
        end
      end
      ACK_PHASE: begin
        if (counter == 16'h0008) begin // ACK/NACK transfer is complete
          state <= IDLE;
          counter <= 16'h0000;
          shift_reg <= '0;
          start_cond <= '0;
          stop_cond <= '1;
        end else begin
          counter <= counter + 16'h0001;
        end
      end
    endcase
  end
end

// Outputs
assign I2C_SDA = (state == IDLE) ? 'Z : (counter[3:0] == 4'b0000) ? start_cond : (counter[3:0] == 4'b1111) ? stop_cond : shift_reg[7];
assign I2C_SCL = (state == IDLE) ? 'Z : (counter[3:0] == 4'b0000) ? '0 : (counter[3:0] == 4'b1111) ? '1 : shift_reg[6];
assign busy = (state != IDLE);
assign data_out = (RW && state == DATA_PHASE) ? shift_reg : '0;

endmodule