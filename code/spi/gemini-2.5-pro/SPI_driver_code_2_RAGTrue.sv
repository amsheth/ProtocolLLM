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

    // Parameter for SPI clock speed.
    // SPI_CLK frequency = clk frequency / (2 * CLK_DIVIDER)
    // Example: 50MHz clk, CLK_DIVIDER=25 -> SPI_CLK = 1MHz
    localparam int CLK_DIVIDER = 4;

    // FSM state definition
    typedef enum logic [1:0] {
        IDLE,
        SETUP,
        TRANSFER,
        CLEANUP
    } state_t;

    state_t state, next_state;

    // Internal registers
    logic [7:0] tx_shift_reg; // Transmit shift register
    logic [7:0] rx_shift_reg; // Receive shift register
    logic [$clog2(CLK_DIVIDER*2)-1:0] clk_counter; // Counter for SPI clock generation
    logic [2:0] bit_counter;  // Counts the 8 bits being transferred

    // Combinational logic for FSM transitions and outputs
    always_comb begin
        // Default assignments to prevent latches
        next_state = state;
        SPI_EN = 1'b1;
        SPI_CLK = 1'b0; // Idle low for CPOL=0
        SPI_MOSI = tx_shift_reg[7];
        data_out = rx_shift_reg;

        case (state)
            IDLE: begin
                SPI_EN = 1'b1;
                if (SPI_start) begin
                    next_state = SETUP;
                end
            end

            SETUP: begin
                SPI_EN = 1'b0;
                next_state = TRANSFER;
            end

            TRANSFER: begin
                SPI_EN = 1'b0;
                // Generate SPI_CLK based on the counter
                // Rising edge is in the first half of the period
                if (clk_counter < CLK_DIVIDER) begin
                    SPI_CLK = 1'b1;
                end else begin
                    SPI_CLK = 1'b0;
                end

                // When the transfer of all bits is complete
                if (bit_counter == 3'd0 && clk_counter == (CLK_DIVIDER*2 - 1)) begin
                    next_state = CLEANUP;
                end
            end

            CLEANUP: begin
                SPI_EN = 1'b1;
                data_out = rx_shift_reg; // Present final received data
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Sequential logic for state and register updates
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx_shift_reg <= 8'h00;
            rx_shift_reg <= 8'h00;
            clk_counter  <= 0;
            bit_counter  <= 3'd7;
        end else begin
            state <= next_state;

            // Logic for SETUP state
            if (state == IDLE && next_state == SETUP) begin
                tx_shift_reg <= data_in;
                rx_shift_reg <= 8'h00; // Clear receive register
                bit_counter  <= 3'd7;
                clk_counter  <= 0;
            end

            // Logic for TRANSFER state
            if (state == TRANSFER) begin
                clk_counter <= clk_counter + 1;

                // CPHA=1: Change data on leading (rising) edge
                // This happens when clk_counter is about to roll over to 0
                if (clk_counter == (CLK_DIVIDER*2 - 1)) begin
                    clk_counter <= 0;
                    // Shift for the next bit, unless it's the last one
                    if (bit_counter != 3'd0) begin
                        tx_shift_reg <= tx_shift_reg << 1;
                        bit_counter <= bit_counter - 1;
                    end
                end

                // CPHA=1: Sample data on trailing (falling) edge
                // This happens when clk_counter reaches the halfway point
                if (clk_counter == CLK_DIVIDER - 1) begin
                    rx_shift_reg <= {rx_shift_reg[6:0], SPI_MISO};
                end
            end
        end
    end

endmodule