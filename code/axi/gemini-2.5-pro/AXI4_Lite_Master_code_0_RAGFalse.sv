module AXI4_Lite_Master(
  // User Interface
  input  logic        clk,          // System clock
  input  logic        rst,          // Asynchronous reset (active high)
  input  logic        AXI_Start,    // Start a new AXI transaction
  input  logic        AXI_WriteEn,  // 1 for write, 0 for read
  input  logic [31:0] AXI_Addr,     // Address for the transaction
  input  logic [31:0] AXI_WData,    // Data to write
  output logic [31:0] AXI_RData,    // Data read from the slave
  output logic        AXI_Done,     // Signals transaction completion for one cycle

  // AXI4-Lite Master Interface Signals
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

  // State machine definition
  typedef enum logic [2:0] {
    IDLE,
    WRITE_ADDR,
    WRITE_DATA,
    WRITE_RESP,
    READ_ADDR,
    READ_DATA,
    DONE
  } state_t;

  state_t current_state, next_state;

  // Internal registers to latch user inputs at the start of a transaction
  logic [31:0] axi_addr_reg;
  logic [31:0] axi_wdata_reg;
  logic        axi_write_en_reg;
  logic [31:0] axi_rdata_reg;

  //----------------------------------------------------------------//
  // Sequential Logic: State and Input Registers                    //
  //----------------------------------------------------------------//

  // State register logic
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      current_state <= IDLE;
    end else begin
      current_state <= next_state;
    end
  end

  // Input latching logic
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      axi_addr_reg     <= 32'b0;
      axi_wdata_reg    <= 32'b0;
      axi_write_en_reg <= 1'b0;
    end else if (current_state == IDLE && AXI_Start) begin
      axi_addr_reg     <= AXI_Addr;
      axi_wdata_reg    <= AXI_WData;
      axi_write_en_reg <= AXI_WriteEn;
    end
  end

  // Read data register
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      axi_rdata_reg <= 32'b0;
    // Latch read data when the slave provides it and we are ready
    end else if (current_state == READ_DATA && M_AXI_RVALID && M_AXI_RREADY) begin
      axi_rdata_reg <= M_AXI_RDATA;
    end
  end

  // Assign registered read data to the output port
  assign AXI_RData = axi_rdata_reg;

  //----------------------------------------------------------------//
  // Combinational Logic: State Transitions and Outputs             //
  //----------------------------------------------------------------//

  always_comb begin
    // Set default values for all outputs to avoid latches
    next_state      = current_state;
    AXI_Done        = 1'b0;

    // AXI signal defaults
    M_AXI_AWVALID   = 1'b0;
    M_AXI_WVALID    = 1'b0;
    M_AXI_BREADY    = 1'b0;
    M_AXI_ARVALID   = 1'b0;
    M_AXI_RREADY    = 1'b0;

    // Drive registered address and data to AXI outputs
    M_AXI_AWADDR  = axi_addr_reg;
    M_AXI_WDATA   = axi_wdata_reg;
    M_AXI_ARADDR  = axi_addr_reg;
    M_AXI_WSTRB   = 4'hF; // AXI4-Lite requires full word writes

    case (current_state)
      IDLE: begin
        if (AXI_Start) begin
          if (axi_write_en_reg) begin // Use registered value
            next_state = WRITE_ADDR;
          end else begin
            next_state = READ_ADDR;
          end
        end
      end

      WRITE_ADDR: begin
        M_AXI_AWVALID = 1'b1;
        if (M_AXI_AWVALID && M_AXI_AWREADY) begin
          next_state = WRITE_DATA;
        end
      end

      WRITE_DATA: begin
        M_AXI_WVALID = 1'b1;
        if (M_AXI_WVALID && M_AXI_WREADY) begin
          next_state = WRITE_RESP;
        end
      end

      WRITE_RESP: begin
        M_AXI_BREADY = 1'b1;
        if (M_AXI_BVALID && M_AXI_BREADY) begin
          next_state = DONE;
        end
      end

      READ_ADDR: begin
        M_AXI_ARVALID = 1'b1;
        if (M_AXI_ARVALID && M_AXI_ARREADY) begin
          next_state = READ_DATA;
        end
      end

      READ_DATA: begin
        M_AXI_RREADY = 1'b1;
        if (M_AXI_RVALID && M_AXI_RREADY) begin
          next_state = DONE;
        end
      end

      DONE: begin
        AXI_Done = 1'b1;
        next_state = IDLE;
      end

      default: begin
        next_state = IDLE;
      end
    endcase
  end

endmodule