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

    // State definitions
    typedef enum logic [1:0] {IDLE, AW, W, B, AR, R} state_t;
    state_t state, next_state;

    // Internal signals
    logic [31:0] awaddr_reg;
    logic [31:0] awdata_reg;
    logic [3:0]  awstrb_reg;
    logic        awvalid_reg;
    logic        wvalid_reg;
    logic        bready_reg;
    logic        arvalid_reg;
    logic        rready_reg;
    logic        done_reg;

    // State transition logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // State machine logic
    always_comb begin
        next_state = state;
        awaddr_reg = awaddr_reg;
        awdata_reg = awdata_reg;
        awstrb_reg = awstrb_reg;
        awvalid_reg = awvalid_reg;
        wvalid_reg = wvalid_reg;
        bready_reg = bready_reg;
        arvalid_reg = arvalid_reg;
        rready_reg = rready_reg;
        done_reg = done_reg;

        case (state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        next_state = AW;
                        awaddr_reg = AXI_Addr;
                        awdata_reg = AXI_WData;
                        awstrb_reg = 4'b1111;
                        awvalid_reg = 1'b1;
                    end else begin
                        next_state = AR;
                        awaddr_reg = AXI_Addr;
                        arvalid_reg = 1'b1;
                    end
                end
            end
            AW: begin
                if (M_AXI_AWREADY) begin
                    next_state = W;
                    awvalid_reg = 1'b0;
                end
            end
            W: begin
                if (M_AXI_WREADY) begin
                    next_state = B;
                    wvalid_reg = 1'b0;
                end
            end
            B: begin
                if (M_AXI_BVALID) begin
                    next_state = IDLE;
                    bready_reg = 1'b1;
                    done_reg = 1'b1;
                end
            end
            AR: begin
                if (M_AXI_ARREADY) begin
                    next_state = R;
                    arvalid_reg = 1'b0;
                end
            end
            R: begin
                if (M_AXI_RVALID) begin
                    next_state = IDLE;
                    rready_reg = 1'b1;
                    AXI_RData = M_AXI_RDATA;
                    done_reg = 1'b1;
                end
            end
        endcase
    end

    // Output logic
    assign M_AXI_AWADDR = awaddr_reg;
    assign M_AXI_AWVALID = awvalid_reg;
    assign M_AXI_WDATA = awdata_reg;
    assign M_AXI_WSTRB = awstrb_reg;
    assign M_AXI_WVALID = wvalid_reg;
    assign M_AXI_BREADY = bready_reg;
    assign M_AXI_ARADDR = awaddr_reg;
    assign M_AXI_ARVALID = arvalid_reg;
    assign M_AXI_RREADY = rready_reg;

    // Done signal
    assign AXI_Done = done_reg;

endmodule