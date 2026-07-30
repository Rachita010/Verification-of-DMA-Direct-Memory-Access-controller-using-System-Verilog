
// 1. DESIGN code

module dma_controller (
  input  logic        clk,
  input  logic        rst_n,

  // Control Registers Interface
  input  logic [31:0] cfg_src_addr,
  input  logic [31:0] cfg_dest_addr,
  input  logic [15:0] cfg_len,        // Transfer length in transfers
  input  logic        cfg_start,
  output logic         cfg_done,

  // AXI4 Master Read Channel
  output logic [31:0] m_axi_araddr,// Read address sent to memory
  output logic [7:0]  m_axi_arlen,// Number of data beats to read (Burst Length)
  output logic         m_axi_arvalid,// Indicates the read address is valid
  input  logic         m_axi_arready,// Memory is ready to accept the read address
  input  logic [31:0] m_axi_rdata,// Data received from memory
  input  logic         m_axi_rlast,// Indicates this is the last data beat of the burst
  input  logic         m_axi_rvalid,// Indicates read data is valid
  output logic         m_axi_rready,// DMA is ready to accept the read data

  // AXI4 Master Write Channel
  output logic [31:0] m_axi_awaddr,// Write address sent to memory
  output logic [7:0]  m_axi_awlen,// Number of data beats to write (Burst Length)
  output logic         m_axi_awvalid,// Indicates the write address is valid
  input  logic         m_axi_awready,// Memory is ready to accept the write address
  output logic [31:0] m_axi_wdata,// Data sent to memory
  output logic         m_axi_wlast,// Indicates the last data beat of the burst
  output logic         m_axi_wvalid,// Indicates write data is valid
  input  logic         m_axi_wready,// Memory is ready to accept write data
  input  logic [1:0]  m_axi_bresp,// Write response from memory (OKAY, ERROR)
  input  logic         m_axi_bvalid,// Indicates the write response is valid
  output logic         m_axi_bready// DMA is ready to accept the write response
);

  typedef enum logic [2:0] {
    IDLE,
    READ_REQ,
    READ_DATA,
    WRITE_REQ,
    WRITE_DATA,
    RESP
  } state_t;

  state_t state;
  logic [15:0] count;
  logic [31:0] fifo_data;
  //FSM 
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= IDLE;
      cfg_done      <= 0;
      m_axi_arvalid <= 0;
      m_axi_rready  <= 0;
      m_axi_awvalid <= 0;
      m_axi_wvalid  <= 0;
      m_axi_bready  <= 0;
      m_axi_araddr  <= 0;
      m_axi_awaddr  <= 0;
      m_axi_wdata   <= 0;
      m_axi_wlast   <= 0;
      m_axi_arlen   <= 0; 
      m_axi_awlen   <= 0; 
      count         <= 0;
    end else begin
      case (state)
        IDLE: begin
          if (cfg_start) begin
            cfg_done     <= 1'b0;
            m_axi_araddr <= cfg_src_addr;
            m_axi_awaddr <= cfg_dest_addr;
            count        <= 0;
            state        <= READ_REQ;
          end
        end

        READ_REQ: begin
          m_axi_arvalid <= 1'b1;
          m_axi_arlen   <= 8'd0; // Single beat
          if (m_axi_arvalid && m_axi_arready) begin
            m_axi_arvalid <= 1'b0;
            m_axi_rready  <= 1'b1;
            state         <= READ_DATA;
          end
        end

        READ_DATA: begin
          if (m_axi_rvalid && m_axi_rready) begin
            fifo_data    <= m_axi_rdata;
            m_axi_rready <= 1'b0;
            state        <= WRITE_REQ;
          end
        end

        WRITE_REQ: begin
          m_axi_awvalid <= 1'b1;
          m_axi_awlen   <= 8'd0;
          if (m_axi_awvalid && m_axi_awready) begin
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b1;
            m_axi_wdata   <= fifo_data;
            m_axi_wlast   <= 1'b1;
            state         <= WRITE_DATA;
          end
        end

        WRITE_DATA: begin
          if (m_axi_wvalid && m_axi_wready) begin
            m_axi_wvalid <= 1'b0;
            m_axi_wlast  <= 1'b0;
            m_axi_bready <= 1'b1;
            state        <= RESP;
          end
        end

        RESP: begin
          if (m_axi_bvalid && m_axi_bready) begin
            m_axi_bready <= 1'b0;
            if (count + 1 == cfg_len) begin
              cfg_done <= 1'b1;
              state    <= IDLE;
            end else begin
              count        <= count + 1'b1;
              m_axi_araddr <= m_axi_araddr + 4;
              m_axi_awaddr <= m_axi_awaddr + 4;
              state        <= READ_REQ;
            end
          end
        end
      endcase
    end
  end
endmodule
