module AXI4_Lite_Master (
    input  logic clk,            // System clock input
    input  logic rst,            // Asynchronous reset input
    input  logic AXI_Start,      // Start a new AXI transaction
    input  logic [31:0] AXI_Addr,// Address for transaction
    input  logic [31:0] AXI_WData,// Data to write
    output logic [31:0] AXI_RData,// Data read from slave
    output logic        AXI_Done, // Transaction complete
    
    // AXI4-Lite signals
    output logic [31:0] M_AXI_AWADDR,
    output logic        M_AXI_AWVALID,
    input  logic        M_AXI_AWREADY,
    output logic [31:0] M_AXI_WDATA,
    output logic [3:0]  M_AXI_WSTRB,
    output logic        M_AXI<s>                                            WVALID,
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
    
    // Internal signals for AXI4-Lite master interface
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        write_en;
    logic        done;
    
    // Address and data register for AXI4-Lite master interface
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            addr <= '0;
            wdata <= '0;
        end else begin
            if (AXI_Start) begin
                addr <= AXI_Addr;
                wdata <= AXI_WData;
            end
        end
    end
    
    // Write enable signal for AXI4-Lite master interface
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            write_en <= '0;
        end else begin
            if (AXI_Start && AXI_WriteEn) begin
                write_en <= 1'b1;
            end else begin
                write_en <= 1'b0;
            end
        end
    end
    
    // Done signal for AXI4-Lite master interface
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            done <= '0;
        end else begin
            if (AXI_Start && !write_en) begin
                done <= 1'b1;
            end else begin
                done <= 1'b0;
            end
        end
    end
    
    // AXI4-Lite master interface signals
    assign M_AXI_AWADDR = addr;
    assign M_AXI_AWVALID = write_en;
    assign M_AXI_WDATA = wdata;
    assign M_AXI_WSTRB = 4'hF;
    assign M_AXI_WVALID = write_en;
    assign M_AXI_ARADDR = addr;
    assign M_AXI_ARVALID = !write_en;
    assign M_AXI_RREADY = done;
    
endmodule