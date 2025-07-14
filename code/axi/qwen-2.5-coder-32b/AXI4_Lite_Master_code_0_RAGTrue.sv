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

    // Internal states
    typedef enum logic [2:0] {
        IDLE,
        WRITE_ADDR,
        WRITE_DATA,
        WRITE_RESP,
        READ_ADDR,
        READ_DATA
    } state_t;

    state_t state, next_state;

    // Registers to hold transaction data
    logic [31:0] addr_reg;
    logic [31:0] wdata_reg;
    logic        write_en_reg;

    // Handshake signals
    logic        awvalid_reg;
    logic        wvalid_reg;
    logic        bready_reg;
    logic        arvalid_reg;
    logic        rready_reg;

    // AXI_Done signal
    logic        done;

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
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
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            addr_reg <= 0;
            wdata_reg <= 0;
            write_en_reg <= 0;
            awvalid_reg <= 0;
            wvalid_reg <= 0;
            bready_reg <= 0;
            arvalid_reg <= 0;
            rready_reg <= 0;
            AXI_RData <= 0;
            AXI_Done <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (AXI_Start) begin
                        addr_reg <= AXI_Addr;
                        wdata_reg <= AXI_WData;
                        write_en_reg <= AXI_WriteEn;
                        AXI_Done <= 0;
                    end
                    awvalid_reg <= 0;
                    wvalid_reg <= 0;
                    bready_reg <= 0;
                    arvalid_reg <= 0;
                    rready_reg <= 0;
                end
                WRITE_ADDR: begin
                    awvalid_reg <= 1;
                    if (M_AXI_AWREADY) begin
                        awvalid_reg <= 0;
                        wvalid_reg <= 1;
                    end
                end
                WRITE_DATA: begin
                    if (M_AXI_WREADY) begin
                        wvalid_reg <= 0;
                        bready_reg <= 1;
                    end
                end
                WRITE_RESP: begin
                    if (M_AXI_BVALID) begin
                        bready_reg <= 0;
                        AXI_Done <= 1;
                    end
                end
                READ_ADDR: begin
                    arvalid_reg <= 1;
                    if (M_AXI_ARREADY) begin
                        arvalid_reg <= 0;
                        rready_reg <= 1;
                    end
                end
                READ_DATA: begin
                    if (M_AXI_RVALID) begin
                        AXI_RData <= M_AXI_RDATA;
                        rready_reg <= 0;
                        AXI_Done <= 1;
                    end
                end
            endcase
        end
    end

    // AXI4-Lite signals assignment
    assign M_AXI_AWADDR = addr_reg;
    assign M_AXI_AWVALID = awvalid_reg;
    assign M_AXI_WDATA = wdata_reg;
    assign M_AXI_WSTRB = 4'b1111; // Assuming all bytes are valid
    assign M_AXI_WVALID = wvalid_reg;
    assign M_AXI_BREADY = bready_reg;
    assign M_AXI_ARADDR = addr_reg;
    assign M_AXI_ARVALID = arvalid_reg;
    assign M_AXI_RREADY = rready_reg;

endmodule