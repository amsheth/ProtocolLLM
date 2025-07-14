module AXI4_Lite_Master(
    input  logic        clk,          // System clock
    input  logic        rst,          // Asynchronous reset (active high)
    input  logic        AXI_Start,    // Start a new AXI transaction (pulse high for one cycle)
    input  logic        AXI_WriteEn,  // 1 for write, 0 for read
    input  logic [31:0] AXI_Addr,     // Address for transaction
    input  logic [31:0] AXI_WData,    // Data to write
    output logic [31:0] AXI_RData,    // Data read from slave
    output logic        AXI_Done,     // Transaction complete (pulsed high for one cycle)

    // AXI4-Lite signals (Master outputs, Slave inputs)
    output logic [31:0] M_AXI_AWADDR,  // Write address
    output logic        M_AXI_AWVALID, // Write address valid
    input  logic        M_AXI_AWREADY, // Write address ready

    output logic [31:0] M_AXI_WDATA,   // Write data
    output logic [3:0]  M_AXI_WSTRB,   // Write strobe (byte enables)
    output logic        M_AXI_WVALID,  // Write data valid
    input  logic        M_AXI_WREADY,  // Write data ready

    input  logic [1:0]  M_AXI_BRESP,   // Write response
    input  logic        M_AXI_BVALID,  // Write response valid
    output logic        M_AXI_BREADY,  // Write response ready

    output logic [31:0] M_AXI_ARADDR,  // Read address
    output logic        M_AXI_ARVALID, // Read address valid
    input  logic        M_AXI_ARREADY, // Read address ready

    input  logic [31:0] M_AXI_RDATA,   // Read data
    input  logic [1:0]  M_AXI_RRESP,   // Read response
    input  logic        M_AXI_RVALID,  // Read data valid
    output logic        M_AXI_RREADY   // Read data ready
);

    // State machine definition
    typedef enum logic [2:0] {
        IDLE,        // Waiting for a new transaction request
        AW_PHASE,    // Sending write address
        W_PHASE,     // Sending write data
        B_PHASE,     // Waiting for write response
        AR_PHASE,    // Sending read address
        R_PHASE,     // Waiting for read data
        DONE_PHASE   // Transaction completed, assert AXI_Done
    } master_state_e;

    master_state_e current_state, next_state;

    // Internal signals for the next values of registered outputs
    // These are calculated in the always_comb block and assigned to registers in always_ff
    logic [31:0] M_AXI_AWADDR_next;
    logic        M_AXI_AWVALID_next;
    logic [31:0] M_AXI_WDATA_next;
    logic [3:0]  M_AXI_WSTRB_next;
    logic        M_AXI_WVALID_next;
    logic        M_AXI_BREADY_next;
    logic [31:0] M_AXI_ARADDR_next;
    logic        M_AXI_ARVALID_next;
    logic        M_AXI_RREADY_next;
    logic [31:0] AXI_RData_next;
    logic        AXI_Done_next;

    // State and Output Registers
    // All outputs are registered to ensure stable signals and meet timing requirements.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            M_AXI_AWADDR  <= 32'b0;
            M_AXI_AWVALID <= 1'b0;
            M_AXI_WDATA   <= 32'b0;
            M_AXI_WSTRB   <= 4'b0;
            M_AXI_WVALID  <= 1'b0;
            M_AXI_BREADY  <= 1'b0;
            M_AXI_ARADDR  <= 32'b0;
            M_AXI_ARVALID <= 1'b0;
            M_AXI_RREADY  <= 1'b0;
            AXI_RData     <= 32'b0;
            AXI_Done      <= 1'b0;
        end else begin
            current_state <= next_state;
            M_AXI_AWADDR  <= M_AXI_AWADDR_next;
            M_AXI_AWVALID <= M_AXI_AWVALID_next;
            M_AXI_WDATA   <= M_AXI_WDATA_next;
            M_AXI_WSTRB   <= M_AXI_WSTRB_next;
            M_AXI_WVALID  <= M_AXI_WVALID_next;
            M_AXI_BREADY  <= M_AXI_BREADY_next;
            M_AXI_ARADDR  <= M_AXI_ARADDR_next;
            M_AXI_ARVALID <= M_AXI_ARVALID_next;
            M_AXI_RREADY  <= M_AXI_RREADY_next;
            AXI_RData     <= AXI_RData_next;
            AXI_Done      <= AXI_Done_next;
        end
    end

    // Combinational logic for next_state and next values of outputs
    always_comb begin
        // Default assignments for next cycle (most signals are de-asserted or hold their value)
        next_state = current_state;

        M_AXI_AWADDR_next  = M_AXI_AWADDR;  // Hold current address unless updated
        M_AXI_AWVALID_next = 1'b0;          // Default to de-asserted
        M_AXI_WDATA_next   = M_AXI_WDATA;   // Hold current data unless updated
        M_AXI_WSTRB_next   = M_AXI_WSTRB;   // Hold current strobe unless updated
        M_AXI_WVALID_next  = 1'b0;          // Default to de-asserted
        M_AXI_BREADY_next  = 1'b0;          // Default to de-asserted
        M_AXI_ARADDR_next  = M_AXI_ARADDR;  // Hold current address unless updated
        M_AXI_ARVALID_next = 1'b0;          // Default to de-asserted
        M_AXI_RREADY_next  = 1'b0;          // Default to de-asserted
        AXI_RData_next     = AXI_RData;     // Hold last read data
        AXI_Done_next      = 1'b0;          // Pulsed signal, default to 0

        case (current_state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        next_state = AW_PHASE;
                        M_AXI_AWADDR_next = AXI_Addr;
                        M_AXI_WDATA_next  = AXI_WData;
                        M_AXI_WSTRB_next  = 4'hF; // Full 32-bit write
                    end else begin
                        next_state = AR_PHASE;
                        M_AXI_ARADDR_next = AXI_Addr;
                    end
                end
            end

            AW_PHASE: begin
                M_AXI_AWVALID_next = 1'b1; // Assert AWVALID
                // AWADDR, WDATA, WSTRB are already set from IDLE, keep them stable
                // M_AXI_AWADDR_next = AXI_Addr; // Redundant, but harmless if AXI_Addr is stable
                // M_AXI_WDATA_next  = AXI_WData;
                // M_AXI_WSTRB_next  = 4'hF;

                if (M_AXI_AWREADY) begin // Handshake complete
                    next_state = W_PHASE;
                    M_AXI_AWVALID_next = 1'b0; // De-assert AWVALID for next cycle
                end
            end

            W_PHASE: begin
                M_AXI_WVALID_next = 1'b1; // Assert WVALID
                // WDATA, WSTRB are already set, keep them stable
                // M_AXI_WDATA_next  = AXI_WData;
                // M_AXI_WSTRB_next  = 4'hF;

                if (M_AXI_WREADY) begin // Handshake complete
                    next_state = B_PHASE;
                    M_AXI_WVALID_next = 1'b0; // De-assert WVALID for next cycle
                end
            end

            B_PHASE: begin
                M_AXI_BREADY_next = 1'b1; // Assert BREADY
                if (M_AXI_BVALID) begin // Handshake complete
                    next_state = DONE_PHASE;
                    M_AXI_BREADY_next = 1'b0; // De-assert BREADY for next cycle
                end
            end

            AR_PHASE: begin
                M_AXI_ARVALID_next = 1'b1; // Assert ARVALID
                // ARADDR is already set from IDLE, keep it stable
                // M_AXI_ARADDR_next = AXI_Addr; // Redundant

                if (M_AXI_ARREADY) begin // Handshake complete
                    next_state = R_PHASE;
                    M_AXI_ARVALID_next = 1'b0; // De-assert ARVALID for next cycle
                end
            end

            R_PHASE: begin
                M_AXI_RREADY_next = 1'b1; // Assert RREADY
                if (M_AXI_RVALID) begin // Handshake complete
                    next_state = DONE_PHASE;
                    AXI_RData_next = M_AXI_RDATA; // Capture read data
                    M_AXI_RREADY_next = 1'b0; // De-assert RREADY for next cycle
                end
            end

            DONE_PHASE: begin
                AXI_Done_next = 1'b1; // Assert AXI_Done for one cycle
                next_state = IDLE;
            end
        endcase
    end

endmodule