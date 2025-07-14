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

    // Parameters for CPOL=1, CPHA=1
    localparam CPOL = 1'b1; // Clock idle high
    localparam CPHA = 1'b1; // Data sampled on trailing edge

    typedef enum logic [1:0] {
        IDLE,
        LOAD,
        TRANSFER,
        DONE
    } state_t;

    state_t state, next_state;
    logic [2:0] bit_cnt;
    logic [7:0] shift_reg_tx;
    logic [7:0] shift_reg_rx;
    logic       spi_clk_int;
    logic       spi_clk_en;
    logic       spi_clk_last;

    // SPI_CLK generation (CPOL=1)
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            spi_clk_int <= CPOL;
        end else if (spi_clk_en) begin
            spi_clk_int <= ~spi_clk_int;
        end else begin
            spi_clk_int <= CPOL;
        end
        spi_clk_last <= spi_clk_int;
    end

    assign SPI_CLK = spi_clk_int;

    // FSM: Next State Logic
    always_comb begin
        next_state = state;
        unique case (state)
            IDLE:     if (SPI_start) next_state = LOAD;
            LOAD:     next_state = TRANSFER;
            TRANSFER: if (bit_cnt == 3'd7 && spi_clk_int==~CPOL && spi_clk_last==CPOL) next_state = DONE;
            DONE:     next_state = IDLE;
            default:  next_state = IDLE;
        endcase
    end

    // FSM: State/Output Logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= IDLE;
            shift_reg_tx  <= 8'd0;
            shift_reg_rx  <= 8'd0;
            bit_cnt       <= 3'd0;
            spi_clk_en    <= 1'b0;
        end else begin
            state <= next_state;
            unique case (state)
                IDLE: begin
                    SPI_EN      <= 1'b1;        // Inactive, /CS deasserted (active low assumed)
                    spi_clk_en  <= 1'b0;
                end
                LOAD: begin
                    shift_reg_tx <= data_in;
                    shift_reg_rx <= 8'd0;
                    bit_cnt      <= 3'd0;
                    SPI_EN       <= 1'b0;       // Active, /CS asserted
                    spi_clk_en   <= 1'b1;
                    // Start clock toggling with a first falling edge, if required
                end
                TRANSFER: begin
                    SPI_EN     <= 1'b0;
                    spi_clk_en <= 1'b1;
                    // SPI_MOSI assignment on leading (first/latching) edge
                    // SPI_MISO sampled on trailing (second/sampling) edge for CPHA=1, CPOL=1
                    if (spi_clk_int == CPOL && spi_clk_last == ~CPOL) begin
                        // Leading edge: Shift data out
                        SPI_MOSI    <= shift_reg_tx[7];
                    end
                    else if (spi_clk_int == ~CPOL && spi_clk_last == CPOL) begin
                        // Trailing edge: Sample data in and shift left
                        shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};
                        shift_reg_rx <= {shift_reg_rx[6:0], SPI_MISO};
                        if (bit_cnt < 3'd7)
                            bit_cnt <= bit_cnt + 3'd1;
                    end
                end
                DONE: begin
                    SPI_EN      <= 1'b1;         // Deassert /CS
                    spi_clk_en  <= 1'b0;
                end
            endcase
        end
    end

    // Output Data Register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'd0;
        end
        else if (state == DONE) begin
            data_out <= shift_reg_rx;
        end
    end

    // SPI MOSI output control
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            SPI_MOSI <= 1'b0;
        end else if (state == LOAD) begin
            SPI_MOSI <= data_in[7];  // MSB first
        end
    end

endmodule