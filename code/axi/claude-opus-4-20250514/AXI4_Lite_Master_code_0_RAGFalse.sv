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

    // State machine states
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        WRITE_ADDR  = 3'b001,
        WRITE_DATA  = 3'b010,
        WRITE_RESP  = 3'b011,
        READ_ADDR   = 3'b100,
        READ_DATA   = 3'b101
    } state_t;

    state_t current_state, next_state;

    // Internal registers
    logic [31:0] addr_reg;
    logic [31:0] wdata_reg;
    logic        write_en_reg;
    
    // State machine sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            addr_reg <= 32'h0;
            wdata_reg <= 32'h0;
            write_en_reg <= 1'b0;
            AXI_RData <= 32'h0;
        end else begin
            current_state <= next_state;
            
            // Capture inputs when starting transaction
            if (current_state == IDLE && AXI_Start) begin
                addr_reg <= AXI_Addr;
                wdata_reg <= AXI_WData;
                write_en_reg <= AXI_WriteEn;
            end
            
            // Capture read data
            if (current_state == READ_DATA && M_AXI_RVALID && M_AXI_RREADY) begin
                AXI_RData <= M_AXI_RDATA;
            end
        end
    end

    // State machine combinational logic
    always_comb begin
        // Default values
        next_state = current_state;
        AXI_Done = 1'b0;
        
        // AXI Write Address Channel
        M_AXI_AWADDR = 32'h0;
        M_AXI_AWVALID = 1'b0;
        
        // AXI Write Data Channel
        M_AXI_WDATA = 32'h0;
        M_AXI_WSTRB = 4'hF;  // All bytes valid
        M_AXI_WVALID = 1'b0;
        
        // AXI Write Response Channel
        M_AXI_BREADY = 1'b0;
        
        // AXI Read Address Channel
        M_AXI_ARADDR = 32'h0;
        M_AXI_ARVALID = 1'b0;
        
        // AXI Read Data Channel
        M_AXI_RREADY = 1'b0;

        case (current_state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        next_state = WRITE_ADDR;
                    end else begin
                        next_state = READ_ADDR;
                    end
                end
            end

            // Write Transaction States
            WRITE_ADDR: begin
                M_AXI_AWADDR = addr_reg;
                M_AXI_AWVALID = 1'b1;
                if (M_AXI_AWREADY) begin
                    next_state = WRITE_DATA;
                end
            end

            WRITE_DATA: begin
                M_AXI_WDATA = wdata_reg;
                M_AXI_WSTRB = 4'hF;
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

            // Read Transaction States
            READ_ADDR: begin
                M_AXI_ARADDR = addr_reg;
                M_AXI_ARVALID = 1'b1;
                if (M_AXI_ARREADY) begin
                    next_state = READ_DATA;
                end
            end

            READ_DATA: begin
                M_AXI_RREADY = 1'b1;
                if (M_AXI_RVALID) begin
                    AXI_Done = 1'b1;
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule