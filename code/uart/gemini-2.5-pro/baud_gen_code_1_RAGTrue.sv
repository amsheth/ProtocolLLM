module baud_gen (
    input  logic clk,
    input  logic rst,
    output logic tick
);
    parameter SYS_CLK_FREQ = 50_000_000; // 50 MHz
    parameter BAUD_RATE    = 9600;
    parameter OVERSAMPLE   = 16;

    localparam COUNTER_MAX = (SYS_CLK_FREQ / (BAUD_RATE * OVERSAMPLE)) - 1;

    logic [$clog2(COUNTER_MAX)-1:0] counter_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            counter_reg <= '0;
            tick        <= 1'b0;
        end else begin
            tick <= 1'b0;
            if (counter_reg == COUNTER_MAX) begin
                counter_reg <= '0;
                tick        <= 1'b1;
            end else begin
                counter_reg <= counter_reg + 1;
            end
        end
    end
endmodule