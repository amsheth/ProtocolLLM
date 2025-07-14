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

    // State encoding
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
    logic [31:0] r_AXI_RData;
    logic AXI_Done_r;

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            AXI_Done_r <= 0;
        end else begin
            state <= next_state;
            AXI_Done_r <= (next_state == DONE);
        end
    end

    // Next state logic
    always_comb begin
        unique case (state)
            IDLE: begin
                if (AXI_Start) begin
                    if (AXI_WriteEn) begin
                        next_state = WRITE_ADDR;
                    end else begin
                        next_state = READ_ADDR;
                    end
                end else begin
                    next_state = IDLE;
                end
            end

            WRITE_ADDR: begin
                if (M_AXI_AWREADY) begin
                    next_state = WRITE_DATA;
                end else begin
                    next_state = WRITE_ADDR;
                end
            end

            WRITE_DATA: begin
                if (M_AXI_WREADY) begin
                    next_state = WRITE_RESP;
                end else begin
                    next_state = WRITE_DATA;
                end
            end

            WRITE_RESP: begin
                if (M_AXI_BVALID) begin
                    next_state = DONE;
                end else begin
                    next_state = WRITE_RESP;
                end
            end

            READ_ADDR: begin
                if (M_AXI_ARREADY) begin
                    next_state = READ_DATA;
                end else begin
                    next_state = READ_ADDR;
                end
            end

            READ_DATA: begin
                if (M_AXI_RVALID) begin
                    next_state = DONE;
                end else begin
                    next_state = READ_DATA;
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

    // Output logic
    always_comb begin
        M_AXI_AWADDR = AXI_Addr;
        M_AXI_AWVALID = (state == WRITE_ADDR);
        M_AXI_WDATA = AXI_WData;
        M_AXI_WSTRB = 4'b1111; // Assuming full word write
        M_AXI_WVALID = (state == WRITE_DATA);
        M_AXI_BREADY = (state == WRITE_RESP);
        M_AXI_ARADDR = AXI_Addr;
        M_AXI_ARVALID = (state == READ_ADDR);
        M_AXI_RREADY = (state == READ_DATA);

        AXI_Done = AXI_Done_r;

        if (state == READ_DATA) begin
            r_AXI_RData = M_AXI_RDATA;
        end else begin
            r_AXI_RData = '0;
        end

        AXI_RData = r_AXI_RData;
    end

endmodule