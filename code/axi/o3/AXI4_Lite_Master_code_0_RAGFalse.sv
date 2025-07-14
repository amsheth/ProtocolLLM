//--------------------------------------------------------------------
// Simple single-beat AXI4-Lite Master
//--------------------------------------------------------------------
module AXI4_Lite_Master
#(
    parameter ADDR_WIDTH = 32 ,
    parameter DATA_WIDTH = 32
)
(
    input  logic                       clk,           // system clock
    input  logic                       rst,           // asynchronous, active-high reset

    // User side
    input  logic                       AXI_Start,     // pulse => start new transaction
    input  logic                       AXI_WriteEn,   // 1 = write, 0 = read
    input  logic  [ADDR_WIDTH-1:0]     AXI_Addr,      // target address
    input  logic  [DATA_WIDTH-1:0]     AXI_WData,     // write data
    output logic  [DATA_WIDTH-1:0]     AXI_RData,     // read data
    output logic                       AXI_Done,      // pulse => transaction complete

    // AXI4-Lite (master) interface
    output logic [ADDR_WIDTH-1:0]      M_AXI_AWADDR,
    output logic                       M_AXI_AWVALID,
    input  logic                       M_AXI_AWREADY,

    output logic [DATA_WIDTH-1:0]      M_AXI_WDATA,
    output logic [3:0]                 M_AXI_WSTRB,
    output logic                       M_AXI_WVALID,
    input  logic                       M_AXI_WREADY,

    input  logic [1:0]                 M_AXI_BRESP,
    input  logic                       M_AXI_BVALID,
    output logic                       M_AXI_BREADY,

    output logic [ADDR_WIDTH-1:0]      M_AXI_ARADDR,
    output logic                       M_AXI_ARVALID,
    input  logic                       M_AXI_ARREADY,

    input  logic [DATA_WIDTH-1:0]      M_AXI_RDATA,
    input  logic [1:0]                 M_AXI_RRESP,
    input  logic                       M_AXI_RVALID,
    output logic                       M_AXI_RREADY
);

//====================================================================
// Local signals / registers
//====================================================================
typedef enum logic [2:0] {
    ST_IDLE        = 3'd0,
    ST_WR_ADDRDATA = 3'd1,
    ST_WR_RESP     = 3'd2,
    ST_RD_ADDR     = 3'd3,
    ST_RD_DATA     = 3'd4
} state_t;

state_t                state , nxt_state;
logic [ADDR_WIDTH-1:0] addr_reg;
logic [DATA_WIDTH-1:0] wdata_reg;
logic                  write_en_reg;

//--------------------------------------------------------------------
// Sequential part
//--------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state        <= ST_IDLE;
        addr_reg     <= '0;
        wdata_reg    <= '0;
        write_en_reg <= 1'b0;
    end
    else begin
        state <= nxt_state;

        // latch command at start
        if (state == ST_IDLE && AXI_Start) begin
            addr_reg     <= AXI_Addr;
            wdata_reg    <= AXI_WData;
            write_en_reg <= AXI_WriteEn;
        end
    end
end

//--------------------------------------------------------------------
// Next-state logic
//--------------------------------------------------------------------
always_comb begin
    nxt_state = state;

    unique case (state)
        ST_IDLE : begin
            if (AXI_Start) begin
                if (AXI_WriteEn) nxt_state = ST_WR_ADDRDATA;
                else             nxt_state = ST_RD_ADDR;
            end
        end

        // -------------- WRITE TRANSACTION --------------------------
        ST_WR_ADDRDATA : begin
            if (M_AXI_AWREADY && M_AXI_WREADY)       // address & data both accepted
                nxt_state = ST_WR_RESP;
        end
        ST_WR_RESP : begin
            if (M_AXI_BVALID)                        // response received
                nxt_state = ST_IDLE;
        end

        // -------------- READ TRANSACTION ---------------------------
        ST_RD_ADDR : begin
            if (M_AXI_ARREADY)                       // address accepted
                nxt_state = ST_RD_DATA;
        end
        ST_RD_DATA : begin
            if (M_AXI_RVALID)                        // data received
                nxt_state = ST_IDLE;
        end

        default : nxt_state = ST_IDLE;
    endcase
end

//--------------------------------------------------------------------
// AXI channel controls
//--------------------------------------------------------------------

// ---------- default assignments ----------
assign M_AXI_WSTRB = 4'hF;           // always writing full 32-bit word

// Write address channel
assign M_AXI_AWADDR  = addr_reg;
assign M_AXI_AWVALID = (state == ST_WR_ADDRDATA);

// Write data channel
assign M_AXI_WDATA   = wdata_reg;
assign M_AXI_WVALID  = (state == ST_WR_ADDRDATA);

// Write response channel
assign M_AXI_BREADY  = (state == ST_WR_RESP);  // assert while waiting

// Read address channel
assign M_AXI_ARADDR  = addr_reg;
assign M_AXI_ARVALID = (state == ST_RD_ADDR);

// Read data channel
assign M_AXI_RREADY  = (state == ST_RD_DATA);

//--------------------------------------------------------------------
// Output data / done flag
//--------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        AXI_RData <= '0;
    else if (state == ST_RD_DATA && M_AXI_RVALID && M_AXI_RREADY)
        AXI_RData <= M_AXI_RDATA;
end

// Done pulse: one clock when transaction finishes
logic done_reg;
always_ff @(posedge clk or posedge rst) begin
    if (rst)
        done_reg <= 1'b0;
    else
        done_reg <= ( (state == ST_WR_RESP && M_AXI_BVALID) ||
                      (state == ST_RD_DATA && M_AXI_RVALID) );
end
assign AXI_Done = done_reg;

endmodule