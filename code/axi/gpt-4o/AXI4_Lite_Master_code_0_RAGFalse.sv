module AXI4_Lite_Master(
    input  logic         clk,          
    input  logic         rst,          
    input  logic         AXI_Start,    
    input  logic         AXI_WriteEn,  
    input  logic [31:0]  AXI_Addr,     
    input  logic [31:0]  AXI_WData,    
    output logic [31:0]  AXI_RData,    
    output logic         AXI_Done,    

    // AXI4-Lite signals
    output logic [31:0]  M_AXI_AWADDR,
    output logic         M_AXI_AWVALID,
    input  logic         M_AXI_AWREADY,

    output logic [31:0]  M_AXI_WDATA,
    output logic [3:0]   M_AXI_WSTRB,
    output logic         M_AXI_WVALID,
    input  logic         M_AXI_WREADY,

    input  logic [1:0]   M_AXI_BRESP,
    input  logic         M_AXI_BVALID,
    output logic         M_AXI_BREADY,

    output logic [31:0]  M_AXI_ARADDR,
    output logic         M_AXI_ARVALID,
    input  logic         M_AXI_ARREADY,

    input  logic [31:0]  M_AXI_RDATA,
    input  logic [1:0]   M_AXI_RRESP,
    input  logic         M_AXI_RVALID,
    output logic         M_AXI_RREADY
);

    typedef enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        // Default values
        M_AXI_AWADDR  = 32'd0;
        M_AXI_AWVALID = 1'b0;
        M_AXI_WDATA   = 32'd0;
        M_AXI_WSTRB   = 4'b0000;
        M_AXI_WVALID  = 1'b0;
        M_AXI_BREADY  = 1'b0;
        M_AXI_ARADDR  = 32'd0;
        M_AXI_ARVALID = 1'b0;
        M_AXI_RREADY  = 1'b0;
        AXI_RData     = 32'd0;
        AXI_Done      = 1'b0;
        
        next_state = state;
        
        case (state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        next_state = WRITE_ADDR;
                    end else begin
                        next_state = READ_ADDR;
                    end
                end
            end

            WRITE_ADDR: begin
                M_AXI_AWADDR  = AXI_Addr;
                M_AXI_AWVALID = 1'b1;
                if (M_AXI_AWREADY) begin
                    next_state = WRITE_DATA;
                end
            end

            WRITE_DATA: begin
                M_AXI_WDATA  = AXI_WData;
                M_AXI_WSTRB  = 4'b1111;
                M_AXI_WVALID = 1'b1;
                if (M_AXI_WREADY) begin
                    next_state = WRITE_RESP;
                end
            end

            WRITE_RESP: begin
                M_AXI_BREADY = 1'b1;
                if (M_AXI_BVALID) begin
                    AXI_Done = 1'b1;
                    next_state = IDLE;
                end
            end

            READ_ADDR: begin
                M_AXI_ARADDR  = AXI_Addr;
                M_AXI_ARVALID = 1'b1;
                if (M_AXI_ARREADY) begin
                    next_state = READ_DATA;
                end
            end

            READ_DATA: begin
                M_AXI_RREADY = 1'b1;
                if (M_AXI_RVALID) begin
                    AXI_RData = M_AXI_RDATA;
                    AXI_Done  = 1'b1;
                    next_state = IDLE;
                end
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
endmodule