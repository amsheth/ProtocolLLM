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

    // Parameter for SPI Clock generation
    // SPI_CLK frequency = clk frequency / CLK_DIVIDER
    parameter CLK_DIVIDER = 4;
    localparam DATA_WIDTH = 8;

    // FSM state definition
    typedef enum logic [1:0] {
        IDLE,
        TRANSFER,
        DONE
    } state_t;

    // Internal registers
    state_t state_reg, next_state;

    logic [7:0] tx_shift_reg; // Transmit shift register
    logic [7:0] rx_shift_reg; // Receive shift register

    // Counter for generating SPI_CLK phases (2 phases per bit)
    logic [$clog2(DATA_WIDTH*2)-1:0] phase_counter;

    // Counter for dividing the main system clock
    logic [$clog2(CLK_DIVIDER/2)-1:0] clk_div_counter;

    // Assign outputs from internal registers
    // This ensures outputs are stable and registered
    assign SPI_MOSI = tx_shift_reg[DATA_WIDTH-1];
    assign SPI_CLK  = state_reg == IDLE ? 1'b1 : phase_counter[0]; // CPOL=1: Idle High
    assign SPI_EN   = state_reg == IDLE;
    assign data_out = rx_shift_reg;


    // FSM State Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg <= IDLE;
        end else begin
            state_reg <= next_state;
        end
    end

    // FSM Combinational Logic (Next State Logic)
    always_comb begin
        next_state = state_reg;
        case (state_reg)
            IDLE: begin
                if (SPI_start) begin
                    next_state = TRANSFER;
                end
            end
            TRANSFER: begin
                // The transfer is complete when the phase counter has counted through
                // all 16 phases (8 bits * 2 phases/bit) and the clock divider is at its end.
                if ((phase_counter == 0) && (clk_div_counter == (CLK_DIVIDER/2 - 1))) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end

    // Data Path and Counter Logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tx_shift_reg    <= '0;
            rx_shift_reg    <= '0;
            phase_counter   <= '0;
            clk_div_counter <= '0;
        end else begin
            case (state_reg)
                IDLE: begin
                    if (SPI_start) begin
                        tx_shift_reg    <= data_in;
                        rx_shift_reg    <= '0; // Clear receive register
                        phase_counter   <= (DATA_WIDTH * 2) - 1; // Start with phase 15
                        clk_div_counter <= '0;
                    end
                end

                TRANSFER: begin
                    // This counter creates the SPI_CLK period from the system clock
                    if (clk_div_counter == (CLK_DIVIDER/2 - 1)) begin
                        clk_div
_counter <= '0;
                        phase_counter   <= phase_counter - 1;

                        // CPHA=1: Sample on trailing edge (LOW -> HIGH transition)
                        // This happens when the phase LSB becomes 1.
                        if (phase_counter[0] == 1'b0) begin
                           rx_shift_reg <= {rx_shift_reg[DATA_WIDTH-2:0], SPI_MISO};
                        end
                        // CPHA=1: Change data on leading edge (HIGH -> LOW transition)
                        // This happens when the phase LSB becomes 0.
                        // We shift the register here to prepare the next bit.
                        else begin
                           tx_shift_reg <= tx_shift_reg << 1;
                        end

                    end else begin
                        clk_div_counter <= clk_div_counter + 1;
                    end
                end

                DONE: begin
                    // In the DONE state, the final received data is already in rx_shift_reg
                    // and assigned to data_out. We just need to ensure counters are ready for
                    // the next IDLE state.
                    phase_counter   <= '0;
                    clk_div_counter <= '0;
                end
            endcase
        end
    end

endmodule