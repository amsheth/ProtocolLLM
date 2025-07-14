module AXI4_Lite_Master(
    input  logic        clk,          // System clock
    input  logic        rst,          // Asynchronous reset
    input  logic        AXI_Start,    // Start a new AXI transaction
    input  logic        AXI_WriteEn,  // 1 for write, 0 for read
    input  logic [31:0] AXI_Addr,     // Address for transaction
    input  logic [31:0] AXI_WData,    // Data to write
    output logic [31:0] AXI_RData,    // Data read from slave
    output logic        AXI_Done,     // Transaction complete
    
    // AXI4-Lite Write Address Channel
    output logic [31:0] M_AXI_AWADDR,
    output logic        M_AXI_AWVALID,
    input  logic        M_AXI_AWREADY,
    
    // AXI4-Lite Write Data Channel
    output logic [31:0] M_AXI_WDATA,
    output logic [3:0]  M_AXI_WSTRB,
    output logic        M_AXI_WVALID,
    input  logic        M_AXI_WREADY,
    
    // AXI4-Lite Write Response Channel
    input  logic [1:0]  M_AXI_BRESP,
    input  logic        M_AXI_BVALID,
    output logic        M_AXI_BREADY,
    
    // AXI4-Lite Read Address Channel
    output logic [31:0] M_AXI_ARADDR,
    output logic        M_AXI_ARVALID,
    input  logic        M_AXI_ARREADY,
    
    // AXI4-Lite Read Data Channel
    input  logic [31:0] M_AXI_RDATA,
    input  logic [1:0]  M_AXI_RRESP,
    input  logic        M_AXI_RVALID,
    output logic        M_AXI_RREADY
);

    // State machine definitions
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        WRITE_ADDR  = 3'b001,
        WRITE_DATA  = 3'b010,
        WRITE_RESP  = 3'b011,
        READ_ADDR   = 3'b100,
        READ_DATA   = 3'b101
    } axi_state_t;

    // Internal registers
    axi_state_t current_state, next_state;
    logic [31:0] addr_reg;
    logic [31:0] wdata_reg;
    logic [31:0] rdata_reg;
    logic        write_en_reg;
    logic        transaction_done;
    logic        aw_done, w_done, b_done;
    logic        ar_done, r_done;

    // Sequential logic for state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            addr_reg      <= 32'h0;
            wdata_reg     <= 32'h0;
            rdata_reg     <= 32'h0;
            write_en_reg  <= 1'b0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            b_done        <= 1'b0;
            ar_done       <= 1'b0;
            r_done        <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // Capture transaction parameters on start
            if (AXI_Start && current_state == IDLE) begin
                addr_reg     <= AXI_Addr;
                wdata_reg    <= AXI_WData;
                write_en_reg <= AXI_WriteEn;
            end
            
            // Track completion of individual channels
            if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                aw_done <= 1'b1;
            end
            
            if (M_AXI_WVALID && M_AXI_WREADY) begin
                w_done <= 1'b1;
            end
            
            if (M_AXI_BVALID && M_AXI_BREADY) begin
                b_done <= 1'b1;
            end
            
            if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                ar_done <= 1'b1;
            end
            
            if (M_AXI_RVALID && M_AXI_RREADY) begin
                r_done <= 1'b1;
                rdata_reg <= M_AXI_RDATA;
            end
            
            // Reset completion flags when returning to IDLE
            if (current_state != IDLE && next_state == IDLE) begin
                aw_done <= 1'b0;
                w_done  <= 1'b0;
                b_done  <= 1'b0;
                ar_done <= 1'b0;
                r_done  <= 1'b0;
            end
        end
    end

    // State machine combinational logic
    always_comb begin
        next_state = current_state;
        
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
            
            WRITE_ADDR: begin
                // Move to WRITE_DATA when both address and data channels are ready
                // or when address is done and we can start data
                if (aw_done || (M_AXI_AWVALID && M_AXI_AWREADY)) begin
                    next_state = WRITE_DATA;
                end
            end
            
            WRITE_DATA: begin
                if (w_done || (M_AXI_WVALID && M_AXI_WREADY)) begin
                    next_state = WRITE_RESP;
                end
            end
            
            WRITE_RESP: begin
                if (b_done || (M_AXI_BVALID && M_AXI_BREADY)) begin
                    next_state = IDLE;
                end
            end
            
            READ_ADDR: begin
                if (ar_done || (M_AXI_ARVALID && M_AXI_ARREADY)) begin
                    next_state = READ_DATA;
                end
            end
            
            READ_DATA: begin
                if (r_done || (M_AXI_RVALID && M_AXI_RREADY)) begin
                    next_state = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

    // AXI4-Lite Write Address Channel
    always_comb begin
        M_AXI_AWADDR  = addr_reg;
        M_AXI_AWVALID = (current_state == WRITE_ADDR) && !aw_done;
    end

    // AXI4-Lite Write Data Channel
    always_comb begin
        M_AXI_WDATA  = wdata_reg;
        M_AXI_WSTRB  = 4'b1111; // All bytes valid for 32-bit transfers
        M_AXI_WVALID = (current_state == WRITE_DATA) && !w_done;
    end

    // AXI4-Lite Write Response Channel
    always_comb begin
        M_AXI_BREADY = (current_state == WRITE_RESP) && !b_done;
    end

    // AXI4-Lite Read Address Channel
    always_comb begin
        M_AXI_ARADDR  = addr_reg;
        M_AXI_ARVALID = (current_state == READ_ADDR) && !ar_done;
    end

    // AXI4-Lite Read Data Channel
    always_comb begin
        M_AXI_RREADY = (current_state == READ_DATA) && !r_done;
    end

    // Output assignments
    always_comb begin
        AXI_RData = rdata_reg;
        AXI_Done  = (current_state != IDLE) && (next_state == IDLE);
    end

endmodule