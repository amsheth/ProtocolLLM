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
    typedef enum logic [3:0] {
        IDLE        = 4'b0000,
        WRITE_ADDR  = 4'b0001,
        WRITE_DATA  = 4'b0010,
        WRITE_RESP  = 4'b0011,
        READ_ADDR   = 4'b0100,
        READ_DATA   = 4'b0101,
        DONE        = 4'b0110
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    logic [31:0] addr_reg;
    logic [31:0] wdata_reg;
    logic [31:0] rdata_reg;
    logic        write_en_reg;
    
    // AXI4-Lite response codes
    localparam [1:0] OKAY   = 2'b00;
    localparam [1:0] EXOKAY = 2'b01;
    localparam [1:0] SLVERR = 2'b10;
    localparam [1:0] DECERR = 2'b11;
    
    // Sequential logic for state machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Input register capture
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            addr_reg     <= 32'h0;
            wdata_reg    <= 32'h0;
            write_en_reg <= 1'b0;
        end else if (current_state == IDLE && AXI_Start) begin
            addr_reg     <= AXI_Addr;
            wdata_reg    <= AXI_WData;
            write_en_reg <= AXI_WriteEn;
        end
    end
    
    // Read data capture
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rdata_reg <= 32'h0;
        end else if (current_state == READ_DATA && M_AXI_RVALID && M_AXI_RREADY) begin
            rdata_reg <= M_AXI_RDATA;
        end
    end
    
    // Combinational logic for state transitions
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
                if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                    next_state = WRITE_DATA;
                end
            end
            
            WRITE_DATA: begin
                if (M_AXI_WVALID && M_AXI_WREADY) begin
                    next_state = WRITE_RESP;
                end
            end
            
            WRITE_RESP: begin
                if (M_AXI_BVALID && M_AXI_BREADY) begin
                    next_state = DONE;
                end
            end
            
            READ_ADDR: begin
                if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                    next_state = READ_DATA;
                end
            end
            
            READ_DATA: begin
                if (M_AXI_RVALID && M_AXI_RREADY) begin
                    next_state = DONE;
                end
            end
            
            DONE: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // AXI4-Lite Write Address Channel
    always_comb begin
        M_AXI_AWADDR  = addr_reg;
        M_AXI_AWVALID = (current_state == WRITE_ADDR);
    end
    
    // AXI4-Lite Write Data Channel
    always_comb begin
        M_AXI_WDATA  = wdata_reg;
        M_AXI_WSTRB  = 4'hF;  // All bytes valid for 32-bit transactions
        M_AXI_WVALID = (current_state == WRITE_DATA);
    end
    
    // AXI4-Lite Write Response Channel
    always_comb begin
        M_AXI_BREADY = (current_state == WRITE_RESP);
    end
    
    // AXI4-Lite Read Address Channel
    always_comb begin
        M_AXI_ARADDR  = addr_reg;
        M_AXI_ARVALID = (current_state == READ_ADDR);
    end
    
    // AXI4-Lite Read Data Channel
    always_comb begin
        M_AXI_RREADY = (current_state == READ_DATA);
    end
    
    // Output assignments
    always_comb begin
        AXI_RData = rdata_reg;
        AXI_Done  = (current_state == DONE);
    end
    
    // Optional: Error handling and response checking
    // This can be extended based on specific requirements
    logic error_flag;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            error_flag <= 1'b0;
        end else begin
            // Check for error responses
            if ((current_state == WRITE_RESP && M_AXI_BVALID && M_AXI_BREADY) ||
                (current_state == READ_DATA && M_AXI_RVALID && M_AXI_RREADY)) begin
                if (write_en_reg) begin
                    error_flag <= (M_AXI_BRESP != OKAY);
                end else begin
                    error_flag <= (M_AXI_RRESP != OKAY);
                end
            end else if (current_state == IDLE) begin
                error_flag <= 1'b0;
            end
        end
    end
    
    // Optional: Timeout counter to prevent hanging
    logic [15:0] timeout_counter;
    localparam TIMEOUT_LIMIT = 16'hFFFF;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            timeout_counter <= 16'h0;
        end else if (current_state == IDLE) begin
            timeout_counter <= 16'h0;
        end else if (current_state != DONE) begin
            timeout_counter <= timeout_counter + 1'b1;
        end
    end
    
    // Timeout error detection
    logic timeout_error;
    assign timeout_error = (timeout_counter >= TIMEOUT_LIMIT);

endmodule