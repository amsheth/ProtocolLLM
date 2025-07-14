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

    // States for the AXI master state machine
    typedef enum logic [2:0] {
        IDLE,
        AW_WAIT_READY,
        W_WAIT_READY,
        B_WAIT_VALID,
        AR_WAIT_READY,
        R_WAIT_VALID
    } axi_state_t;

    axi_state_t state, next_state;
    logic       start_reg;
    logic       write_en_reg;
    logic [31:0] addr_reg;
    logic [31:0] wdata_reg;
    logic [31:0] rdata_reg;
    logic        done_reg;

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            start_reg <= 0;
            write_en_reg <= 0;
            addr_reg <= 0;
            wdata_reg <= 0;
            rdata_reg <= 0;
            done_reg <= 0;
        end else begin
            state <= next_state;

            // Register inputs on transaction start
            if (AXI_Start) begin
                start_reg <= AXI_Start;
                write_en_reg <= AXI_WriteEn;
                addr_reg <= AXI_Addr;
                wdata_reg <= AXI_WData;
            end

            // Clear done signal after it is asserted
            if (done_reg)
                done_reg <= 0;

        end
    end

    // Next state logic
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (AXI_Start) begin
                    if (write_en_reg)
                        next_state = AW_WAIT_READY;
                    else
                        next_state = AR_WAIT_READY;
                end
            end

            AW_WAIT_READY: begin
                if (M_AXI_AWREADY)
                    next_state = W_WAIT_READY;
            end

            W_WAIT_READY: begin
                if (M_AXI_WREADY)
                    next_state = B_WAIT_VALID;
            end

            B_WAIT_VALID: begin
                if (M_AXI_BVALID) begin
                    done_reg <= 1;
                    next_state = IDLE;
                end
            end

            AR_WAIT_READY: begin
                if (M_AXI_ARREADY)
                    next_state = R_WAIT_VALID;
            end

            R_WAIT_VALID: begin
                if (M_AXI_RVALID) begin
                    rdata_reg <= M_AXI_RDATA;
                    done_reg <= 1;
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Output assignments
    always_comb begin
        M_AXI_AWADDR = addr_reg;
        M_AXI_AWVALID = (state == AW_WAIT_READY);
        M_AXI_WDATA = wdata_reg;
        M_AXI_WSTRB = 4'b1111; // Assuming all bytes are valid
        M_AXI_WVALID = (state == W_WAIT_READY);
        M_AXI_BREADY = (state == B_WAIT_VALID);
        M_AXI_ARADDR = addr_reg;
        M_AXI_ARVALID = (state == AR_WAIT_READY);
        M_AXI_RREADY = (state == R_WAIT_VALID);

        AXI_RData = rdata_reg;
        AXI_Done = done_reg;
    end

endmodule