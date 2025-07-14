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

    typedef enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA
    } state_t;

    state_t state, next_state;

    // Internal signals
    logic [31:0] rdata_reg;
    logic        done_reg;

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            done_reg <= 0;
        end else begin
            state <= next_state;
            done_reg <= 0;
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
                    next_state = IDLE;
            end
            READ_ADDR: begin
                if (M_AXI_ARREADY)
                    next_state = READ_DATA;
            end
            READ_DATA: begin
                if (M_AXI_RVALID)
                    next_state = IDLE;
            end
        endcase
    end

    // Output logic
    always_comb begin
        // Default assignments
        M_AXI_AWADDR  = '0;
        M_AXI_AWVALID = 0;
        M_AXI_WDATA   = '0;
        M_AXI_WSTRB   = '0;
        M_AXI_WVALID  = 0;
        M_AXI_BREADY  = 0;
        M_AXI_ARADDR  = '0;
        M_AXI_ARVALID = 0;
        M_AXI_RREADY  = 0;
        AXI_RData     = '0;
        AXI_Done      = done_reg;

        case (state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        M_AXI_AWADDR  = AXI_Addr;
                        M_AXI_AWVALID = 1;
                    end else begin
                        M_AXI_ARADDR  = AXI_Addr;
                        M_AXI_ARVALID = 1;
                    end
                end
            end
            WRITE_ADDR: begin
                if (M_AXI_AWREADY) begin
                    M_AXI_WDATA   = AXI_WData;
                    M_AXI_WSTRB   = 4'b1111; // Assuming full word write
                    M_AXI_WVALID  = 1;
                end
            end
            WRITE_DATA: begin
                if (M_AXI_WREADY) begin
                    M_AXI_BREADY  = 1;
                end
            end
            WRITE_RESP: begin
                if (M_AXI_BVALID) begin
                    done_reg = 1;
                end
            end
            READ_ADDR: begin
                if (M_AXI_ARREADY) begin
                    M_AXI_RREADY  = 1;
                end
            end
            READ_DATA: begin
                if (M_AXI_RVALID) begin
                    AXI_RData = M_AXI_RDATA;
                    done_reg = 1;
                end
            end
        endcase
    end

endmodule