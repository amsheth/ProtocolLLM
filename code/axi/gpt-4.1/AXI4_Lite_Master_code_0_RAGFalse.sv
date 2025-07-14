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

    typedef enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA,
        DONE
    } state_t;

    state_t state, next_state;

    // Internal registers to hold transaction info
    logic [31:0] addr_reg, wdata_reg;
    logic        write_en_reg;

    // Sequential state and data registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            addr_reg    <= 32'd0;
            wdata_reg   <= 32'd0;
            write_en_reg<= 1'b0;
        end else begin
            state       <= next_state;
            if (state == IDLE && AXI_Start) begin
                addr_reg     <= AXI_Addr;
                wdata_reg    <= AXI_WData;
                write_en_reg <= AXI_WriteEn;
            end
        end
    end

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn)
                        next_state = WRITE_ADDR;
                    else
                        next_state = READ_ADDR;
                end
            end
            WRITE_ADDR: begin
                if (M_AXI_AWREADY)
                    next_state = WRITE_DATA;
            end
            WRITE_DATA: begin
                if (M_AXI_WREADY)
                    next_state = WRITE_RESP;
            end
            WRITE_RESP: begin
                if (M_AXI_BVALID)
                    next_state = DONE;
            end
            READ_ADDR: begin
                if (M_AXI_ARREADY)
                    next_state = READ_DATA;
            end
            READ_DATA: begin
                if (M_AXI_RVALID)
                    next_state = DONE;
            end
            DONE: begin
                if (!AXI_Start)
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Output and handshake logic
    // Default assignments
    assign M_AXI_AWADDR  = (state == WRITE_ADDR) ? addr_reg : 32'd0;
    assign M_AXI_AWVALID = (state == WRITE_ADDR);
    assign M_AXI_WDATA   = (state == WRITE_DATA) ? wdata_reg : 32'd0;
    assign M_AXI_WSTRB   = 4'b1111;
    assign M_AXI_WVALID  = (state == WRITE_DATA);
    assign M_AXI_BREADY  = (state == WRITE_RESP);

    assign M_AXI_ARADDR  = (state == READ_ADDR) ? addr_reg : 32'd0;
    assign M_AXI_ARVALID = (state == READ_ADDR);
    assign M_AXI_RREADY  = (state == READ_DATA);

    assign AXI_Done      = (state == DONE);

    // Latch read data when valid
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            AXI_RData <= 32'd0;
        end else if (state == READ_DATA && M_AXI_RVALID) begin
            AXI_RData <= M_AXI_RDATA;
        end
    end

endmodule