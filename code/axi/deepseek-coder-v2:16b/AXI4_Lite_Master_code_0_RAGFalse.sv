module AXI4_Lite_Master(
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

    typedef enum {IDLE, AWWAIT, WWAIT, BWAIT, ARWAIT, RWAIT} state_t;
    state_t state, next_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        case (state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        next_state = AWWAIT;
                    end else begin
                        next_state = ARWAIT;
                    end
                end else begin
                    next_state = IDLE;
                end
            end
            AWWAIT: begin
                if (M_AXI_AWREADY) begin
                    next_state = WWAIT;
                end else begin
                    next_state = AWWAIT;
                end
            end
            WWAIT: begin
                if (M_AXI_WREADY && M_AXI_BVALID) begin
                    next_state = BWAIT;
                end else begin
                    next_state = WWAIT;
                end
            end
            BWAIT: begin
                if (M_AXI_BREADY) begin
                    next_state = IDLE;
                end else begin
                    next_state = BWAIT;
                end
            end
            ARWAIT: begin
                if (M_AXI_ARREADY) begin
                    next_state = RWAIT;
                end else begin
                    next_state = ARWAIT;
                end
            end
            RWAIT: begin
                if (M_AXI_RVALID) begin
                    next_state = IDLE;
                end else begin
                    next_state = RWAIT;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            M_AXI_AWADDR  <= 32'b0;
            M_AXI_AWVALID <= 1'b0;
            M_AXI_WDATA   <= 32'b0;
            M_AXI_WSTRB   <= 4'b0;
            M_AXI_WVALID  <= 1'b0;
            M_AXI_ARADDR  <= 32'b0;
            M_AXI_ARVALID <= 1'b0;
            M_AXI_BREADY  <= 1'b0;
            M_AXI_RREADY  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (AXI_Start) begin
                        if (AXI_WriteEn) begin
                            M_AXI_AWADDR  <= AXI_Addr;
                            M_AXI_AWVALID <= 1'b1;
                            M_AXI_WDATA   <= AXI_WData;
                            M_AXI_WSTRB   <= 4'hf; // Assuming full byte access
                            M_AXI_WVALID  <= 1'b1;
                        end else begin
                            M_AXI_ARADDR  <= AXI_Addr;
                            M_AXI_ARVALID <= 1'b1;
                        end
                    end
                end
                AWWAIT: begin
                    if (M_AXI_AWREADY) begin
                        M_AXI_WVALID <= 1'b1;
                    end
                end
                WWAIT: begin
                    if (M_AXI_WREADY && M_AXI_BVALID) begin
                        M_AXI_BREADY <= 1'b1;
                    end
                end
                BWAIT: begin
                    if (M_AXI_BREADY) begin
                        M_AXI_BREADY <= 1'b0;
                    end
                end
                ARWAIT: begin
                    if (M_AXI_ARREADY) begin
                        M_AXI_RREADY <= 1'b1;
                    end
                end
                RWAIT: begin
                    if (M_AXI_RVALID) begin
                        AXI_RData <= M_AXI_RDATA;
                        M_AXI_RREADY <= 1'b0;
                    end
                end
            endcase
        end
    end

endmodule