module AXI4_Lite_Master(
    input  logic        clk,          // System clock
    input  logic        rst,          // Asynchronous reset
    input  logic        AXI_Start,    // Start a new AXI transaction (pulse for one cycle)
    input  logic        AXI_WriteEn,  // 1 for write, 0 for read
    input  logic [31:0] AXI_Addr,     // Address for transaction
    input  logic [31:0] AXI_WData,    // Data to write
    output logic [31:0] AXI_RData,    // Data read from slave
    output logic        AXI_Done,     // Transaction complete (pulsed for one cycle)

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

    // State machine definition
    typedef enum logic [2:0] {
        IDLE,         // Waiting for a transaction request
        WRITE_ADDR,   // Sending write address
        WRITE_DATA,   // Sending write data
        WRITE_RESP,   // Waiting for write response
        READ_ADDR,    // Sending read address
        READ_DATA     // Waiting for read data
    } master_state_e;

    master_state_e current_state, next_state;

    // Internal registers for AXI output signals and AXI_Done
    logic [31:0] awaddr_reg;
    logic        awvalid_reg;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;
    logic        wvalid_reg;
    logic        bready_reg;
    logic [31:0] araddr_reg;
    logic        arvalid_reg;
    logic [31:0] rdata_reg;
    logic        rready_reg;
    logic        axi_done_reg;

    // Assign outputs from internal registers
    assign M_AXI_AWADDR  = awaddr_reg;
    assign M_AXI_AWVALID = awvalid_reg;
    assign M_AXI_WDATA   = wdata_reg;
    assign M_AXI_WSTRB   = wstrb_reg;
    assign M_AXI_WVALID  = wvalid_reg;
    assign M_AXI_BREADY  = bready_reg;
    assign M_AXI_ARADDR  = araddr_reg;
    assign M_AXI_ARVALID = arvalid_reg;
    assign AXI_RData     = rdata_reg;
    assign M_AXI_RREADY  = rready_reg;
    assign AXI_Done      = axi_done_reg;

    // State register logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state and output logic
    always_comb begin
        // Default assignments to deassert AXI VALID/READY signals and AXI_Done
        // This prevents unintended latches and ensures signals are low when not active.
        next_state    = current_state;
        awvalid_reg   = 1'b0;
        wvalid_reg    = 1'b0;
        bready_reg    = 1'b0;
        arvalid_reg   = 1'b0;
        rready_reg    = 1'b0;
        axi_done_reg  = 1'b0; // AXI_Done is pulsed for one cycle

        // Default data/address assignments (will be overridden by state logic when needed)
        awaddr_reg    = 32'b0;
        wdata_reg     = 32'b0;
        wstrb_reg     = 4'hF; // Default to full 32-bit write strobe
        araddr_reg    = 32'b0;
        rdata_reg     = 32'b0;

        case (current_state)
            IDLE: begin
                if (AXI_Start) begin
                    // Latch input values at the start of a transaction
                    awaddr_reg = AXI_Addr;
                    araddr_reg = AXI_Addr;
                    wdata_reg  = AXI_WData;

                    if (AXI_WriteEn) begin
                        next_state = WRITE_ADDR;
                    end else begin
                        next_state = READ_ADDR;
                    end
                end
            end

            WRITE_ADDR: begin
                awvalid_reg = 1'b1; // Assert AWVALID
                awaddr_reg  = AXI_Addr; // Ensure address is stable
                if (M_AXI_AWREADY) begin
                    next_state = WRITE_DATA; // Slave is ready for address
                end
            end

            WRITE_DATA: begin
                wvalid_reg = 1'b1; // Assert WVALID
                wdata_reg  = AXI_WData; // Ensure data is stable
                wstrb_reg  = 4'hF; // Full 32-bit write
                if (M_AXI_WREADY) begin
                    next_state = WRITE_RESP; // Slave is ready for data
                end
            end

            WRITE_RESP: begin
                bready_reg = 1'b1; // Assert BREADY
                if (M_AXI_BVALID) begin
                    next_state   = IDLE;       // Write response received, go back to IDLE
                    axi_done_reg = 1'b1;       // Pulse AXI_Done
                end
            end

            READ_ADDR: begin
                arvalid_reg = 1'b1; // Assert ARVALID
                araddr_reg  = AXI_Addr; // Ensure address is stable
                if (M_AXI_ARREADY) begin
                    next_state = READ_DATA; // Slave is ready for address
                end
            end

            READ_DATA: begin
                rready_reg = 1'b1; // Assert RREADY
                if (M_AXI_RVALID) begin
                    rdata_reg    = M_AXI_RDATA; // Capture read data
                    next_state   = IDLE;       // Read data received, go back to IDLE
                    axi_done_reg = 1'b1;       // Pulse AXI_Done
                end
            end

            default: begin
                // Should not reach here, but as a safeguard, return to IDLE
                next_state = IDLE;
            end
        endcase
    end

endmodule