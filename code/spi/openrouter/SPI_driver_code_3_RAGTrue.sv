module SPI_driver (
    input   logic                    clk,          // System clock
    input   logic                    rst,          // System reset (active high)
    input   logic [7:0]              data_in,      // Data to be transmitted
    input   logic                    SPI_MISO,     // Master In Slave Out (input from external device)
    input   logic                    SPI_start,    // Start signal for SPI transfer
    output  logic                    SPI_MOSI,     // Master Out Slave In (output to external device)
    output  logic                    SPI_CLK,      // Serial Clock
    output  logic                    SPI_EN,       // Slave Enable (Chip Select)
    output  logic [7:0]              data_out      // Data received from external device
);

// State machine states
typedef enum {
    IDLE,
    SHIFTING,
    DONE
} state_t;

state_t state = IDLE;

// Counter for bit shifting
reg [3:0] bit_cnt = 4'b0;

// Data registers for transmitting and receiving
reg [7:0] tx_data = 8'h0;
reg [7:0] rx_data = 8'h0;

// Clock enable
reg        clock_en = 1'h0;

// Clock for generating the SCLK waveform
reg        sclk_i = 1'h0;

// Internal register for MISO input
reg        miso_reg = 1'h0;

// Module initialization
always_ff @ (posedge clk) begin
    if (rst) begin
        state  <= IDLE;
        bit_cnt <= 4'h0;
        tx_data <= 8'h0;
        rx_data <= 8'h0;
        clock_en <= 1'h0;
        sclk_i <= 1'h0;
        miso_reg <= 1'h0;
        SPI_CLK <= 1'h0;
        SPI_EN  <= 1'h1;  // CS starts high (assuming active low CS)
    end else begin
        // State machine
        case (state)
            IDLE: begin
                SPI_EN <= 1'h1;  // CS high (assuming active low)
                SPI_CLK <= 1'h0; // SCLK low in IDLE state (CPOL=0)
                
                if (SPI_start) begin
                    state <= SHIFTING;
                    bit_cnt <= 4'h0;
                    tx_data <= data_in;  // Load transmit data
                    rx_data <= 8'h0;
                    clock_en <= 1'h1;    // Enable clock generation
                end
            end

            SHIFTING: begin
                if (clock_en) begin
                    // Generate SCLK waveform
                    sclk_i = ~sclk_i;
                    
                    // On rising edge of SCLK (for CPHA=0)
                    if (sclk_i) begin
                        // Send next bit to MOSI
                        SPI_MOSI <= tx_data[7];  // MSB first
                        tx_data <= tx_data << 1;
                        
                        // Receive new bit from MISO
                        miso_reg <= SPI_MISO;
                        rx_data[7 - bit_cnt] <= miso_reg;
                        
                        bit_cnt <= bit_cnt + 1;
                        
                        // After all bits are shifted
                        if (bit_cnt == 4'h8) begin
                            state <= DONE;
                        end
                    end
                end
            end

            DONE: begin
                SPI_CLK <= 1'h0;
                SPI_EN <= 1'h1;  // CS high (assuming active low)
                clock_en <= 1'h0; // Stop clock generation
                data_out <= rx_data;
                state <= IDLE;
            end
        endcase
    end
end

// SCLK generation (CPOL=0, CPHA=0)
always_ff @ (posedge clk) begin
    if (clock_en) begin
        sclk_i <= ~sclk_i;
    end
end

// Output signals
assign SPI_MOSI = tx_data[7];  // MSB first for transmission
assign SPI_CLK  = sclk_i;       // SCLK waveform
assign SPI_EN   = ~SPI_EN;      // Assuming active low CS, invert the signal

endmodule