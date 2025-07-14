module AXI4_Lite_Master (
    input  logic        clk,          // System clock input
    input  logic        rst,          // Asynchronous reset input
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

    // State machine states
    typedef enum {
        IDLE,
        SEND_AW,
        WAIT_AWREADY,
        SEND_W,
        WAIT_WREADY,
        SEND_WLAST,
        WAIT_B,
        SEND_AR,
        WAIT_ARREADY,
        SEND_R,
        WAIT_R
    } state_type;

    state_type state = IDLE;

    // AXI transaction signals
    reg [31:0] addr;
    reg [31:0] wdata;
    reg [3:0]  wstrb;  // Strobes for each byte in 32-bit data
    reg        done = 0;

    // Initialize write strobes for full 32-bit write
    initial begin
        wstrb = 4'b1111;  // All bytes are written (32 bits)
    end

    always @(posedge clk) begin
        if (rst) begin
            state          <= IDLE;
            M_AXI_AWVALID  <= 0;
            M_AXI_WVALID   <= 0;
            M_AXI_WLAST    <= 0;
            M_AXI_ARVALID  <= 0;
            M_AXI_RREADY   <= 0;
            M_AXI_BREADY   <= 0;
            done           <= 0;
        end else begin
            case (state)
                IDLE: begin
                    // Reset outputs
                    M_AXI_AWVALID  <= 0;
                    M_AXI_WVALID   <= 0;
                    M_AXI_WLAST    <= 0;
                    M_AXI_ARVALID  <= 0;
                    M_AXI_RREADY   <= 0;
                    M_AXI_BREADY   <= 0;

                    if (AXI_Start) begin
                        addr <= AXI_Addr;
                        wdata <= AXI_WData;
                        if (AXI_WriteEn) begin
                            state <= SEND_AW;
                            M_AXI_AWADDR <= addr;
                            M_AXI_AWVALID <= 1;
                        end else begin
                            state <= SEND_AR;
                            M_AXI_ARADDR <= addr;
                            M_AXI_ARVALID <= 1;
                        end
                    end
                end

                SEND_AW: begin
                    if (M_AXI_AWREADY) begin
                        state <= WAIT_AWREADY;
                    end
                end

                WAIT_AWREADY: begin
                    if (M_AXI_AWREADY) begin
                        state <= SEND_W;
                        M_AXI_WDATA <= wdata;
                        M_AXI_WSTRB <= wstrb;
                        M_AXI_WVALID <= 1;
                    end
                end

                SEND_W: begin
                    if (M_AXI_WREADY) begin
                        state <= WAIT_WREADY;
                        M_AXI_WLAST <= 1;
                    end
                end

                WAIT_WREADY: begin
                    if (M_AXI_WREADY) begin
                        state <= WAIT_B;
                        M_AXI_WREADY <= 1;
                        M_AXI_WVALID <= 0;
                    end
                end

                WAIT_B: begin
                    if (M_AXI_BVALID) begin
                        state <= IDLE;
                        AXI_RData = 0;  // No data for write response
                        done <= 1;
                        M_AXI_BREADY <= 1;
                    end
                end

                SEND_AR: begin
                    if (M_AXI_ARREADY) begin
                        state <= WAIT_ARREADY;
                    end
                end

                WAIT_ARREADY: begin
                    if (M_AXI_ARREADY) begin
                        state <= SEND_R;
                        M_AXI_ARVALID <= 1;
                    end
                end

                SEND_R: begin
                    if (M_AXI_RVALID) begin
                        AXI_RData <= M_AXI_RDATA;
                        state <= WAIT_R;
                    end
                end

                WAIT_R: begin
                    if (M_AXI_RVALID) begin
                        done <= 1;
                        M_AXI_RREADY <= 1;
                        state <= IDLE;
                    end
                end

                default: begin
                    // Handle unexpected states if any
                    state <= IDLE;
                end
            endcase
        end
    end

    // AXI_DONE output logic
    assign AXI_Done = done;
endmodule