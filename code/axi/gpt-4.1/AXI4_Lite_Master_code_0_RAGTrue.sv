module AXI4_Lite_Master(
    input  logic        clk,           // System clock
    input  logic        rst,           // Asynchronous reset, active high

    input  logic        AXI_Start,     // Start new AXI transaction
    input  logic        AXI_WriteEn,   // 1 for write, 0 for read
    input  logic [31:0] AXI_Addr,      // Address for transaction
    input  logic [31:0] AXI_WData,     // Data to write
    output logic [31:0] AXI_RData,     // Data read from slave
    output logic        AXI_Done,      // Transaction complete

    // AXI4-Lite write address channel
    output logic [31:0] M_AXI_AWADDR,
    output logic        M_AXI_AWVALID,
    input  logic        M_AXI_AWREADY,

    // AXI4-Lite write data channel
    output logic [31:0] M_AXI_WDATA,
    output logic [3:0]  M_AXI_WSTRB,
    output logic        M_AXI_WVALID,
    input  logic        M_AXI_WREADY,

    // AXI4-Lite write response channel
    input  logic [1:0]  M_AXI_BRESP,
    input  logic        M_AXI_BVALID,
    output logic        M_AXI_BREADY,

    // AXI4-Lite read address channel
    output logic [31:0] M_AXI_ARADDR,
    output logic        M_AXI_ARVALID,
    input  logic        M_AXI_ARREADY,

    // AXI4-Lite read data channel
    input  logic [31:0] M_AXI_RDATA,
    input  logic [1:0]  M_AXI_RRESP,
    input  logic        M_AXI_RVALID,
    output logic        M_AXI_RREADY
);

    // AXI protocol state machine
    typedef enum logic [2:0] {
        IDLE         = 3'b000,
        WRITE_ADDR   = 3'b001,
        WRITE_DATA   = 3'b010,
        WRITE_RESP   = 3'b011,
        READ_ADDR    = 3'b100,
        READ_DATA    = 3'b101
    } state_t;

    state_t state, next_state;

    // Registers to store latched values
    logic [31:0] latched_addr;
    logic [31:0] latched_wdata;

    // Default assignments
    assign M_AXI_AWADDR  = (state == WRITE_ADDR ) ? latched_addr  : 32'b0;
    assign M_AXI_WDATA   = (state == WRITE_DATA ) ? latched_wdata : 32'b0;
    assign M_AXI_WSTRB   = 4'hF;  // always write all bytes
    assign M_AXI_ARADDR  = (state == READ_ADDR  ) ? latched_addr  : 32'b0;

    // Sequential state machine and latching signals
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= IDLE;
            latched_addr  <= 32'b0;
            latched_wdata <= 32'b0;
        end else begin
            state <= next_state;
            // Latch address and data at start
            if (state == IDLE && AXI_Start) begin
                latched_addr  <= AXI_Addr;
                latched_wdata <= AXI_WData;
            end
        end
    end

    // Combinatorial state machine logic
    always_comb begin
        // Default/hold values
        M_AXI_AWVALID = 1'b0;
        M_AXI_WVALID  = 1'b0;
        M_AXI_BREADY  = 1'b0;
        M_AXI_ARVALID = 1'b0;
        M_AXI_RREADY  = 1'b0;
        AXI_Done      = 1'b0;

        next_state    = state;

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
            M_AXI_AWVALID = 1'b1;
            if (M_AXI_AWREADY) begin
                next_state = WRITE_DATA;
            end
        end

        WRITE_DATA: begin
            M_AXI_WVALID = 1'b1;
            if (M_AXI_WREADY) begin
                next_state = WRITE_RESP;
            end
        end

        WRITE_RESP: begin
            M_AXI_BREADY = 1'b1;
            if (M_AXI_BVALID) begin
                next_state = IDLE;
                AXI_Done   = 1'b1;
            end
        end

        READ_ADDR: begin
            M_AXI_ARVALID = 1'b1;
            if (M_AXI_ARREADY) begin
                next_state = READ_DATA;
            end
        end

        READ_DATA: begin
            M_AXI_RREADY = 1'b1;
            if (M_AXI_RVALID) begin
                next_state = IDLE;
                AXI_Done   = 1'b1;
            end
        end

        default: next_state = IDLE;
        endcase
    end

    // Latch AXI_RData when read valid
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            AXI_RData <= 32'b0;
        end else if (state == READ_DATA && M_AXI_RVALID && M_AXI_RREADY) begin
            AXI_RData <= M_AXI_RDATA;
        end
    end

endmodule