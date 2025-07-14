module AXI4_Lite_Master
(
    input  logic        clk,            // System clock
    input  logic        rst,            // Asynchronous active-high reset

    input  logic        AXI_Start,      // 1-cycle pulse to start a transfer
    input  logic        AXI_WriteEn,    // 1 = write, 0 = read
    input  logic [31:0] AXI_Addr,       // byte address (word-aligned preferred)
    input  logic [31:0] AXI_WData,      // write data
    output logic [31:0] AXI_RData,      // read data
    output logic        AXI_Done,       // 1-cycle pulse when finished

    // --------------- AXI4-Lite Master Signals -------------------
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

// -----------------------------------------------------------------------------
// Internal state & registers
// -----------------------------------------------------------------------------
typedef enum logic [2:0] { S_IDLE,          // waiting for AXI_Start
                           S_W_ADDR,        // write address
                           S_W_DATA,        // write data
                           S_W_RESP,        // wait for B channel
                           S_R_ADDR,        // read address
                           S_R_DATA         // wait for R channel
                         } state_t;

state_t  state, nstate;

logic [31:0] addr_latched;     // stores address of ongoing transaction
logic [31:0] wdata_latched;    // stores write data
logic        w_en_latched;     // latched direction (write/read)

logic        done_int;         // internal done pulse

// -----------------------------------------------------------------------------
// Sequential block
// -----------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state         <= S_IDLE;
        addr_latched  <= 32'd0;
        wdata_latched <= 32'd0;
        w_en_latched  <= 1'b0;
    end
    else begin
        state <= nstate;

        // Latch inputs only when a new transaction starts
        if (AXI_Start && state==S_IDLE) begin
            addr_latched  <= AXI_Addr;
            wdata_latched <= AXI_WData;
            w_en_latched  <= AXI_WriteEn;
        end
    end
end

// -----------------------------------------------------------------------------
// Next-state logic
// -----------------------------------------------------------------------------
always_comb begin
    nstate = state;
    unique case (state)
        //-------------------------------------------
        S_IDLE: begin
            if (AXI_Start) begin
                nstate = (AXI_WriteEn) ? S_W_ADDR : S_R_ADDR;
            end
        end
        //-------------------------------------------
        // WRITE sequence
        S_W_ADDR: begin
            if (M_AXI_AWREADY && M_AXI_AWVALID)
                nstate = S_W_DATA;
        end
        S_W_DATA: begin
            if (M_AXI_WREADY && M_AXI_WVALID)
                nstate = S_W_RESP;
        end
        S_W_RESP: begin
            if (M_AXI_BVALID)
                nstate = S_IDLE;           // single transaction done
        end
        //-------------------------------------------
        // READ sequence
        S_R_ADDR: begin
            if (M_AXI_ARREADY && M_AXI_ARVALID)
                nstate = S_R_DATA;
        end
        S_R_DATA: begin
            if (M_AXI_RVALID)
                nstate = S_IDLE;           // single transaction done
        end
        //-------------------------------------------
        default: nstate = S_IDLE;
    endcase
end

// -----------------------------------------------------------------------------
// AXI signal generation
// -----------------------------------------------------------------------------
assign M_AXI_AWADDR  = addr_latched;
assign M_AXI_WDATA   = wdata_latched;
assign M_AXI_WSTRB   = 4'b1111;          // full 32-bit write
assign M_AXI_ARADDR  = addr_latched;

// VALID signals
assign M_AXI_AWVALID = (state == S_W_ADDR);   // assert until AWREADY
assign M_AXI_WVALID  = (state == S_W_DATA);   // assert until WREADY
assign M_AXI_ARVALID = (state == S_R_ADDR);   // assert until ARREADY

// READY outputs (from master to slave)
assign M_AXI_BREADY  = (state == S_W_RESP);   // accept response immediately
assign M_AXI_RREADY  = (state == S_R_DATA);   // ready to grab read data

// -----------------------------------------------------------------------------
// Completion pulse & read-data capture
// -----------------------------------------------------------------------------
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        AXI_RData <= 32'd0;
        done_int  <= 1'b0;
    end
    else begin
        done_int <= 1'b0;                    // default: de-assert

        // Capture READ data when it arrives
        if (state==S_R_DATA && M_AXI_RVALID && M_AXI_RREADY) begin
            AXI_RData <= M_AXI_RDATA;
            done_int  <= 1'b1;               // generate done pulse
        end

        // Capture WRITE response
        if (state==S_W_RESP && M_AXI_BVALID && M_AXI_BREADY) begin
            done_int  <= 1'b1;               // generate done pulse
        end
    end
end

assign AXI_Done = done_int;

// -----------------------------------------------------------------------------
// Unused responses ( BRESP / RRESP ) could be checked for SLVERR/DECERR here
// -----------------------------------------------------------------------------

endmodule