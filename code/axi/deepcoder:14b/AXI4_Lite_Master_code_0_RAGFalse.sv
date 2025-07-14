module AXI4_Lite_Master (
    input  logic        clk,
    input  logic        rst,
    input  logic        AXI_Start,
    input  logic        AXI_WriteEn,
    input  logic [31:0] AXI_Addr,
    input  logic [31:0] AXI_WData,
    output logic [31:0] AXI_RData,
    output logic        AXI_Done,

    // AXI4-Lite signals
    output logic [31:0] M_AXI_AWADDR,
    output logic        M_AXI_AWVALID,
    input  logic        M_AXI_AWREADY,

    output logic [31:0] M_AXI_WDATA,
    output logic [3:0]  M_AXI_WSTRB,
    output logic        M_AXI_WVALID,
    input  logic        M_AXI_WREADY,

    input  logic [1:0]  M_AXI_BRESP,
    input  logic        M_AXI_BVALID,
    output logic        M_AXI_BREADY,

    output logic [31:0] M_AXI_ARADDR,
    output logic        M_AXI_ARVALID,
    input  logic        M_AXI_ARREADY,

    input  logic [31:0] M_AXI_RDATA,
    input  logic [1:0]  M_AXI_RRESP,
    input  logic        M_AXI_RVALID,
    output logic        M_AXI_RREADY
);

// State machine to handle AXI4-Lite transactions
typedef enum {
    IDLE,
    ADDR_PHASE,
    DATA_PHASE,
    DONE
} state_t;

state_t state = IDLE;

// Internal signals to store transaction information
logic [31:0] waddr;
logic [31:0] wdata;
logic        is_write;

// AXI handshake flags
logic aw_ready, ar_ready, w_ready, b_valid, r_valid;

always_ff @(posedge clk) begin
    if (rst) begin
        state          <= IDLE;
        aw_ready       <= 0;
        ar_ready       <= 0;
        w_ready        <= 0;
        b_valid        <= 0;
        r_valid        <= 0;
        is_write       <= 0;
        waddr          <= 0;
        wdata          <= 0;
        AXI_RData      <= 0;
        AXI_Done       <= 0;

        // AXI4-Lite signals
        M_AXI_AWVALID  <= 0;
        M_AXI_WVALID   <= 0;
        M_AXI_BREADY    <= 0;
        M_AXI_ARVALID  <= 0;
        M_AXI_RREADY    <= 0;
    end else begin
        case (state)
            IDLE: begin
                // Wait for new transaction start
                if (AXI_Start) begin
                    state          <= ADDR_PHASE;
                    is_write       <= AXI_WriteEn;
                    waddr          <= AXI_Addr;
                    wdata          <= AXI_WData;

                    // Reset handshake flags
                    aw_ready       <= 0;
                    ar_ready       <= 0;
                    w_ready        <= 0;
                    b_valid        <= 0;
                    r_valid        <= 0;
                end else begin
                    state          <= IDLE;
                end

                // AXI4-Lite signals
                M_AXI_AWVALID  <= 0;
                M_AXI_WVALID   <= 0;
                M_AXI_BREADY    <= 0;
                M_AXI_ARVALID  <= 0;
                M_AXI_RREADY    <= 0;

                // AXI_RData and AXI_Done
                AXI_RData      <= 0;
                AXI_Done       <= 0;
            end

            ADDR_PHASE: begin
                // Send address phase signals
                if (is_write) begin
                    M_AXI_AWADDR   <= waddr;
                    M_AXI_AWVALID  <= 1;

                    if (M_AXI_AWREADY) begin
                        aw_ready       <= 1;
                        state          <= DATA_PHASE;
                        M_AXI_WDATA    <= wdata;
                        M_AXI_WSTRB    <= 4'b1111; // Write all 4 bytes
                        M_AXI_WVALID   <= 1;

                        if (M_AXI_WREADY) begin
                            w_ready        <= 1;
                            state          <= DONE;
                        end
                    end
                end else begin
                    M_AXI_ARADDR    <= waddr;
                    M_AXI_ARVALID   <= 1;

                    if (M_AXI_ARREADY) begin
                        ar_ready       <= 1;
                        state          <= DONE;
                    end
                end

                // AXI4-Lite signals
                M_AXI_BREADY      <= 1; // Always ready for response
            end

            DATA_PHASE: begin
                // Wait for write response or read data
                if (is_write) begin
                    if (b_valid) begin
                        state          <= IDLE;
                        AXI_Done       <= 1;
                    end
                end else begin
                    if (r_valid) begin
                        AXI_RData      <= M_AXI_RDATA;
                        state          <= IDLE;
                        AXI_Done       <= 1;
                    end
                end

                // AXI4-Lite signals
                M_AXI_BREADY      <= 1; // Always ready for response
            end

            DONE: begin
                // Reset handshake flags
                aw_ready       <= 0;
                ar_ready       <= 0;
                w_ready        <= 0;
                b_valid        <= 0;
                r_valid        <= 0;

                state          <= IDLE;
            end
        endcase

        // Update AXI4-Lite response flags
        if (M_AXI_BVALID) begin
            b_valid        <= 1;
        end else if (!rst) begin
            b_valid        <= 0;
        end

        if (M_AXI_RVALID) begin
            r_valid        <= 1;
        end else if (!rst) begin
            r_valid        <= 0;
        end
    end
end

// AXI4-Lite signals
assign M_AXI_AWVALID = (state == ADDR_PHASE && is_write);
assign M_AXI_WVALID  = (state == DATA_PHASE && is_write);
assign M_AXI_BREADY   = 1; // Always ready for response
assign M_AXI_ARVALID  = (state == ADDR_PHASE && !is_write);
assign M_AXI_RREADY    = 1; // Always ready for read responses

// AXI4-Lite responses
assign AXI_Done       = (state == DONE);

endmodule