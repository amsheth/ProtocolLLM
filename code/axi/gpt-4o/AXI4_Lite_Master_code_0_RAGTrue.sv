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

typedef enum logic [1:0] {
    IDLE,
    WRITE_ADDR,
    WRITE_DATA,
    READ_ADDR,
    READ_DATA,
    WAIT_RESP
} state_t;

state_t state, next_state;

// Ensure all outputs have an initial value
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
        M_AXI_AWADDR <= 32'b0;
        M_AXI_AWVALID <= 1'b0;
        M_AXI_WDATA <= 32'b0;
        M_AXI_WSTRB <= 4'b1111;
        M_AXI_WVALID <= 1'b0;
        M_AXI_BREADY <= 1'b0;
        M_AXI_ARADDR <= 32'b0;
        M_AXI_ARVALID <= 1'b0;
        M_AXI_RREADY <= 1'b0;
        AXI_RData <= 32'b0;
        AXI_Done <= 1'b0;
    end else begin
        state <= next_state;
        
        case (state)
            IDLE: begin
                AXI_Done <= 1'b0;
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        M_AXI_AWADDR <= AXI_Addr;
                        M_AXI_AWVALID <= 1'b1;
                        next_state <= WRITE_ADDR;
                    end else begin
                        M_AXI_ARADDR <= AXI_Addr;
                        M_AXI_ARVALID <= 1'b1;
                        next_state <= READ_ADDR;
                    end
                end
            end
            
            WRITE_ADDR: begin
                if (M_AXI_AWREADY) begin
                    M_AXI_AWVALID <= 1'b0;
                    M_AXI_WDATA <= AXI_WData;
                    M_AXI_WVALID <= 1'b1;
                    next_state <= WRITE_DATA;
                end
            end
            
            WRITE_DATA: begin
                if (M_AXI_WREADY) begin
                    M_AXI_WVALID <= 1'b0;
                    M_AXI_BREADY <= 1'b1;
                    next_state <= WAIT_RESP;
                end
            end

            WAIT_RESP: begin
                if (M_AXI_BVALID) begin
                    M_AXI_BREADY <= 1'b0;
                    AXI_Done <= 1'b1;
                    next_state <= IDLE;
                end
            end
            
            READ_ADDR: begin
                if (M_AXI_ARREADY) begin
                    M_AXI_ARVALID <= 1'b0;
                    M_AXI_RREADY <= 1'b1;
                    next_state <= READ_DATA;
                end
            end
            
            READ_DATA: begin
                if (M_AXI_RVALID) begin
                    AXI_RData <= M_AXI_RDATA;
                    AXI_Done <= 1'b1;
                    M_AXI_RREADY <= 1'b0;
                    next_state <= IDLE;
                end
            end
            
            default: next_state <= IDLE;
        endcase
    end
end

endmodule