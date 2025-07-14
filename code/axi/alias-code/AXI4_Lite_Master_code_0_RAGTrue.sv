module AXI4_Lite_Master(
    input  logic        clk,          // System clock
    input  logic        rst,          // Asynchronous reset
    input  logic        AXI_Start,    // Start a new AXI transaction
    input  logic        AXI_WriteEn,  // 1 for write, 0 for read
    input  logic [31:0] AXI_Addr,     // Address for transaction
    input  logic [31:0] AXI_WData,    // Data to write
    output logic [31:0] AXI_RData,    // Data read from slave
    output logic        AXI_Done,     // Transaction complete

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

    // Internal signals
    logic [31:0] awaddr_reg;
    logic        awvalid_reg;
    logic        wvalid_reg;
    logic        bready_reg;
    logic [31:0] araddr_reg;
    logic        arvalid_reg;
    logic        rready_reg;
    logic [31:0] rdata_reg;
    logic [1:0]  bresp_reg;
    logic        bvalid_reg;
    logic        done_reg;

    // State machine states
    typedef enum logic [1:0] {IDLE, AW, W, B, AR, R} state_t;
    state_t state, next_state;

    // State machine logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        awaddr_reg = awaddr_reg;
        awvalid_reg = awvalid_reg;
        wvalid_reg = wvalid_reg;
        bready_reg = bready_reg;
        araddr_reg = araddr_reg;
        arvalid_reg = arvalid_reg;
        rready_reg = rready_reg;
        rdata_reg = rdata_reg;
        bresp_reg = bresp_reg;
        bvalid_reg = bvalid_reg;
        done_reg = done_reg;

        case (state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        next_state = AW;
                    end else begin
                        next_state = AR;
                    end
                end
            end
            AW: begin
                awaddr_reg = AXI_Addr;
                awvalid_reg = 1;
                if (M_AXI_AWREADY) begin
                    next_state = W;
                end
            end
            W: begin
                M_AXI_WDATA = AXI_WData;
                M_AXI_WSTRB = 15; // Assuming 32-bit data width
                M_AXI_WVALID = 1;
                if (M_AXI_WREADY) begin
                    next_state = B;
                end
            end
            B: begin
                bready_reg = 1;
                if (M_AXI_BVALID) begin
                    bresp_reg = M_AXI_BRESP;
                    bvalid_reg = 1;
                    next_state = IDLE;
                end
            end
            AR: begin
                araddr_reg = AXI_Addr;
                arvalid_reg = 1;
                if (M_AXI_ARREADY) begin
                    next_state = R;
                end
            end
            R: begin
                rready_reg = 1;
                if (M_AXI_RVALID) begin
                    rdata_reg = M_AXI_RDATA;
                    rvalid_reg = 1;
                    next_state = IDLE;
                end
            end
        endcase
    end

    // Output logic
    assign M_AXI_AWADDR = awaddr_reg;
    assign M_AXI_AWVALID = awvalid_reg;
    assign M_AXI_WDATA = AXI_WData;
    assign M_AXI_WSTRB = 15; // Assuming 32-bit data width
    assign M_AXI_WVALID = wvalid_reg;
    assign M_AXI_BREADY = bready_reg;
    assign M_AXI_ARADDR = araddr_reg;
    assign M_AXI_ARVALID = arvalid_reg;
    assign M_AXI_RREADY = rready_reg;
    assign AXI_RData = rdata_reg;
    assign AXI_Done = done_reg;

endmodule