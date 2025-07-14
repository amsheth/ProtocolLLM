module SPI_driver (
    input  logic        clk,
    input  logic        rst,
    input  logic [7:0]  data_in,
    input  logic        SPI_MISO,
    input  logic        SPI_start,
    output logic        SPI_MOSI,
    output logic        SPI_CLK,
    output logic        SPI_EN,
    output logic [7:0]  data_out
);

    // SPI Mode Parameters: CPOL=1, CPHA=1
    localparam CPOL = 1;
    localparam CPHA = 1;

    // FSM States
    typedef enum logic [1:0] {
        S_IDLE,
        S_TRANSFER,
        S_DONE
    } state_t;

    // Internal Registers
    state_t     state_reg, state_next;
    logic [7:0] tx_reg, tx_reg_next;
    logic [7:0] rx_reg, rx_reg_next;
    logic [3:0] edge_count_reg, edge_count_next;
    logic       spi_clk_internal;

    // Sequential Logic (Registers)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg      <= S_IDLE;
            tx_reg         <= 8'h00;
            rx_reg         <= 8'h00;
            edge_count_reg <= 4'd0;
            SPI_EN         <= 1'b1;
            data_out       <= 8'h00;
        end else begin
            state_reg      <= state_next;
            tx_reg         <= tx_reg_next;
            rx_reg         <= rx_reg_next;
            edge_count_reg <= edge_count_next;

            // Register outputs to avoid glitches
            if (state_next == S_IDLE) begin
                SPI_EN <= 1'b1;
            end else if (state_reg == S_IDLE && state_next == S_TRANSFER) begin
                SPI_EN <= 1'b0;
            end

            if (state_next == S_DONE) begin
                data_out <= rx_reg_next;
            end
        end
    end

    // Combinational Logic (Next State and Outputs)
    always_comb begin
        // Default assignments to avoid latches
        state_next      = state_reg;
        tx_reg_next     = tx_reg;
        rx_reg_next     = rx_reg;
        edge_count_next = edge_count_reg;
        
        // Default MOSI output is the current MSB of the transmit register
        SPI_MOSI = tx_reg[7];

        case (state_reg)
            S_IDLE: begin
                if (SPI_start) begin
                    state_next      = S_TRANSFER;
                    tx_reg_next     = data_in;
                    rx_reg_next     = 8'h00;
                    // Start counting 16 edges (8 clock cycles)
                    edge_count_next = 4'd15;
                end
            end

            S_TRANSFER: begin
                // Decrement edge counter on each system clock cycle
                edge_count_next = edge_count_reg - 1;

                // For CPOL=1, CPHA=1:
                // Idle clock is High.
                // Leading edge is Low-to-High. Data is changed here.
                // Trailing edge is High-to-Low. Data is sampled here.
                
                // The internal SPI clock is high for even edge counts (14, 12, ... 0)
                // and low for odd edge counts (15, 13, ... 1).
                // This logic determines the action based on the *upcoming* clock edge.
                
                // If edge_count is odd, next clock state is low (trailing edge H->L)
                if (edge_count_reg[0] == 1'b1) begin 
                    // Sample MISO on the trailing edge
                    rx_reg_next = {rx_reg[6:0], SPI_MISO};
                end
                // If edge_count is even, next clock state is high (leading edge L->H)
                else begin 
                    // Change MOSI on the leading edge by shifting the register
                    tx_reg_next = {tx_reg[6:0], 1'b0};
                end

                // After the last edge (count reaches 0), move to DONE state
                if (edge_count_reg == 4'd0) begin
                    state_next = S_DONE;
                end
            end

            S_DONE: begin
                // Transition back to IDLE on the next clock cycle
                state_next = S_IDLE;
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    // SPI Clock Generation
    // In IDLE/DONE state, clock is held at CPOL value (1)
    // In TRANSFER state, clock toggles. It's high on even counts, low on odd counts.
    assign spi_clk_internal = (state_reg == S_TRANSFER) ? ~edge_count_reg[0] : CPOL;
    assign SPI_CLK = spi_clk_internal;

endmodule