module AXI4_Lite_Master(
  // User Interface
  input  logic        clk,          // System clock
  input  logic        rst,          // Asynchronous reset (active high)
  input  logic        AXI_Start,    // Start a new AXI transaction
  input  logic        AXI_WriteEn,  // 1 for write, 0 for read
  input  logic [31:0] AXI_Addr,     // Address for transaction
  input  logic [31:0] AXI_WData,    // Data to write
  output logic [31:0] AXI_RData,    // Data read from slave
  output logic        AXI_Done,     // Transaction complete pulse

  // AXI4-Lite Master Interface
  // Write Address Channel
  output logic [31:0] M_AXI_AWADDR,
  output logic        M_AXI_AWVALID,
  input  logic        M_AXI_AWREADY,

  // Write Data Channel
  output logic [31:0] M_AXI_WDATA,
  output logic [3:0]  M_AXI_WSTRB,
  output logic        M_AXI_WVALID,
  input  logic        M_AXI_WREADY,

  // Write Response Channel
  input  logic [1:0]  M_AXI_BRESP,
  input  logic        M_AXI_BVALID,
  output logic        M_AXI_BREADY,

  // Read Address Channel
  output logic [31:0] M_AXI_ARADDR,
  output logic        M_AXI_ARVALID,
  input  logic        M_AXI_ARREADY,

  // Read Data Channel
  input  logic [31:0] M_AXI_RDATA,
  input  logic [1:0]  M_AXI_RRESP,
  input  logic        M_AXI_RVALID,
  output logic        M_AXI_RREADY
);

  // FSM state definition
  typedef enum logic [2:0] {
    S_IDLE,
    S_WRITE_ADDR_DATA,
    S_WRITE_RESP,
    S_READ_ADDR,
    S_READ_DATA,
    S_DONE
  } state_t;

  state_t state_reg, next_state;

  // Internal registers to hold transaction properties
  logic [31:0] addr_reg;
  logic [31:0] wdata_reg;

  //----------------------------------------------------------------
  // Sequential Logic: State and Data Registers
  //----------------------------------------------------------------
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state_reg <= S_IDLE;
      addr_reg  <= 32'b0;
      wdata_reg <= 32'b0;
      AXI_RData <= 32'b0;
    end else begin
      state_reg <= next_state;

      // Latch user inputs when a new transaction starts
      if (state_reg == S_IDLE && AXI_Start) begin
        addr_reg  <= AXI_Addr;
        wdata_reg <= AXI_WData;
      end

      // Latch read data from the slave when the read data handshake completes
      if (state_reg == S_READ_DATA && M_AXI_RVALID && M_AXI_RREADY) begin
        AXI_RData <= M_AXI_RDATA;
      end
    end
  end

  //----------------------------------------------------------------
  // Combinational Logic: FSM Transitions and Output Control
  //----------------------------------------------------------------
  always_comb begin
    // Default assignments
    next_state      = state_reg;
    AXI_Done        = 1'b0;
    M_AXI_AWVALID   = 1'b0;
    M_AXI_WVALID    = 1'b0;
    M_AXI_BREADY    = 1'b0;
    M_AXI_ARVALID   = 1'b0;
    M_AXI_RREADY    = 1'b0;

    case (state_reg)
      S_IDLE: begin
        // Wait for a start signal from the user
        if (AXI_Start) begin
          if (AXI_WriteEn) begin
            next_state = S_WRITE_ADDR_DATA;
          end else begin
            next_state = S_READ_ADDR;
          end
        end
      end

      S_WRITE_ADDR_DATA: begin
        // Assert address and data valid signals for a write
        M_AXI_AWVALID = 1'b1;
        M_AXI_WVALID  = 1'b1;
        // Wait for slave to accept both address and data
        if (M_AXI_AWREADY && M_AXI_WREADY) begin
          next_state = S_WRITE_RESP;
        end
      end

      S_WRITE_RESP: begin
        // Ready to accept the write response from the slave
        M_AXI_BREADY = 1'b1;
        // Wait for a valid response from the slave
        if (M_AXI_BVALID) begin
          next_state = S_DONE;
        end
      end

      S_READ_ADDR: begin
        // Assert address valid for a read
        M_AXI_ARVALID = 1'b1;
        // Wait for slave to accept the address
        if (M_AXI_ARREADY) begin
          next_state = S_READ_DATA;
        end
      end

      S_READ_DATA: begin
        // Ready to accept read data from the slave
        M_AXI_RREADY = 1'b1;
        // Wait for valid data from the slave
        if (M_AXI_RVALID) begin
          next_state = S_DONE;
        end
      end

      S_DONE: begin
        // Assert Done for one cycle to signal completion to the user
        AXI_Done = 1'b1;
        next_state = S_IDLE;
      end

      default: begin
        next_state = S_IDLE;
      end
    endcase
  end

  //----------------------------------------------------------------
  // Continuous Assignments
  //----------------------------------------------------------------
  // Drive AXI signals from internal registers
  assign M_AXI_AWADDR = addr_reg;
  assign M_AXI_WDATA  = wdata_reg;
  assign M_AXI_ARADDR = addr_reg;

  // WSTRB is fixed to write all 4 bytes for 32-bit transactions
  assign M_AXI_WSTRB  = 4'b1111;

endmodule