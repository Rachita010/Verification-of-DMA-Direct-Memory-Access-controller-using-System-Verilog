//=============================================================================
// 1. INTERFACE code
//=============================================================================
interface dma_intf (input logic clk, input logic rst_n);
  // Control Interface
  logic [31:0] cfg_src_addr;
  logic [31:0] cfg_dest_addr;
  logic [15:0] cfg_len;
  logic        cfg_start;
  logic        cfg_done;

  // AXI Read Channel
  logic [31:0] m_axi_araddr;
  logic [7:0]  m_axi_arlen;
  logic        m_axi_arvalid;
  logic        m_axi_arready;
  logic [31:0] m_axi_rdata;
  logic        m_axi_rlast;
  logic        m_axi_rvalid;
  logic        m_axi_rready;

  // AXI Write Channel
  logic [31:0] m_axi_awaddr;
  logic [7:0]  m_axi_awlen;
  logic        m_axi_awvalid;
  logic        m_axi_awready;
  logic [31:0] m_axi_wdata;
  logic        m_axi_wlast;
  logic        m_axi_wvalid;
  logic        m_axi_wready;
  logic [1:0]  m_axi_bresp;
  logic        m_axi_bvalid;
  logic        m_axi_bready;
endinterface


//=============================================================================
// 2. TRANSACTION code
//=============================================================================
class transaction;
  typedef enum bit {WRITE, READ} kind_e;

  kind_e kind;

  rand bit [31:0] src_addr;
  rand bit [31:0] dest_addr;
  rand bit [15:0] transfer_len;
  rand bit [31:0] payload[];

  constraint align_c {
    src_addr[1:0]  == 2'b00;
    dest_addr[1:0] == 2'b00;
    transfer_len inside {[1:10]};
    payload.size() == transfer_len;
  }

  
  function transaction copy();
    transaction t = new();
    t.kind         = this.kind;
    t.src_addr     = this.src_addr;
    t.dest_addr    = this.dest_addr;
    t.transfer_len = this.transfer_len;
    t.payload      = this.payload;
    return t;
  endfunction

  function void display(string name);
    $display("-----------------------------------------");
    $display(" - %s (%s)", name, kind.name());
    $display("-----------------------------------------");
    $display("SRC_ADDR: 0x%0h | DEST_ADDR: 0x%0h | LEN: %0d", src_addr, dest_addr, transfer_len);
    foreach (payload[i]) begin
      $display(" Data[%0d]: 0x%0h", i, payload[i]);
    end
    $display("-----------------------------------------");
  endfunction
endclass


//=============================================================================
// 3. GENERATOR code
//=============================================================================
class generator;
  rand transaction trans;
  int repeat_count;
  mailbox gen2driv;
  mailbox gen2scb; 
  event ended;

  typedef struct {
    bit [31:0] addr;
    bit [15:0] len;
  } mem_block_t;

  mem_block_t written_blocks[$];

  function new(mailbox gen2driv, mailbox gen2scb);
    this.gen2driv = gen2driv;
    this.gen2scb  = gen2scb;
  endfunction

  task main();
    repeat (repeat_count) begin
      trans = new();

      if (written_blocks.size() == 0)
        trans.kind = transaction::WRITE;
      else
        trans.kind = transaction::kind_e'($urandom_range(0, 1));

      if (trans.kind == transaction::WRITE) begin
        if (!trans.randomize()) $fatal("GEN:: Randomization Failed!");

        
        begin
          mem_block_t blk;
          blk.addr = trans.dest_addr;   
          blk.len  = trans.transfer_len;
          written_blocks.push_back(blk);
        end

      end else begin
        int idx;
        mem_block_t blk;

        idx = $urandom_range(0, written_blocks.size() - 1);
        blk = written_blocks[idx];

        trans.src_addr     = blk.addr;      
        trans.transfer_len = blk.len;        
        trans.payload      = new[blk.len];   
        trans.dest_addr    = ($urandom & 32'hFFFF_FFFC); 
      end

      trans.display("GENERATOR");
      gen2driv.put(trans);
      gen2scb.put(trans.copy()); 
    end
    -> ended;
  endtask
endclass


//=============================================================================
// 4. DRIVER code
//=============================================================================
class driver;
  int no_transactions;
  virtual dma_intf vif;
  mailbox gen2driv;

  
  bit [31:0] mem_array[bit [31:0]];

  function new(virtual dma_intf vif, mailbox gen2driv);
    this.vif = vif;
    this.gen2driv = gen2driv;
  endfunction

  task reset();
    wait (!vif.rst_n);
    $display("[DRIVER] ----- Reset Started -----");
    vif.cfg_start <= 0;
    vif.cfg_src_addr <= 0;
    vif.cfg_dest_addr <= 0;
    vif.cfg_len <= 0;
    vif.m_axi_arready <= 0;
    vif.m_axi_rvalid <= 0;
    vif.m_axi_rdata <= 0;
    vif.m_axi_rlast <= 0;
    vif.m_axi_awready <= 0;
    vif.m_axi_wready <= 0;
    vif.m_axi_bvalid <= 0;
    vif.m_axi_bresp <= 0;
    wait (vif.rst_n);
    $display("[DRIVER] ----- Reset Ended -----");
  endtask

  task main();
    transaction trans;
    forever begin
      gen2driv.get(trans);

      // Kick off Configuration
      @(posedge vif.clk);
      vif.cfg_src_addr <= trans.src_addr;
      vif.cfg_dest_addr <= trans.dest_addr;
      vif.cfg_len <= trans.transfer_len;
      vif.cfg_start <= 1'b1;
      @(posedge vif.clk);
      vif.cfg_start <= 1'b0;

      fork
        
        for (int i = 0; i < trans.transfer_len; i++) begin
          bit [31:0] req_addr;
          bit [31:0] rd_data;

          wait (vif.m_axi_arvalid);
          req_addr = vif.m_axi_araddr; 
          @(posedge vif.clk);
          vif.m_axi_arready <= 1'b1;
          @(posedge vif.clk);
          vif.m_axi_arready <= 1'b0;

          if (trans.kind == transaction::WRITE) begin
           
            rd_data = trans.payload[i];
          end else begin
            
            rd_data = mem_array.exists(req_addr) ? mem_array[req_addr] : 32'hDEAD_BEEF;
          end

          vif.m_axi_rvalid <= 1'b1;
          vif.m_axi_rdata  <= rd_data;
          vif.m_axi_rlast  <= 1'b1;
          wait (vif.m_axi_rready);
          @(posedge vif.clk);
          vif.m_axi_rvalid <= 1'b0;
          vif.m_axi_rlast  <= 1'b0;
        end


        for (int i = 0; i < trans.transfer_len; i++) begin
          bit [31:0] req_addr;

          wait (vif.m_axi_awvalid);
          req_addr = vif.m_axi_awaddr;
          @(posedge vif.clk);
          vif.m_axi_awready <= 1'b1;
          @(posedge vif.clk);
          vif.m_axi_awready <= 1'b0;

          wait (vif.m_axi_wvalid);
          @(posedge vif.clk);
          vif.m_axi_wready <= 1'b1;

          
          wait (vif.m_axi_wvalid && vif.m_axi_wready);
          if (trans.kind == transaction::WRITE)
            mem_array[req_addr] = vif.m_axi_wdata;

          @(posedge vif.clk);
          vif.m_axi_wready <= 1'b0;
          vif.m_axi_bvalid <= 1'b1;
          vif.m_axi_bresp <= 2'b00;
          wait (vif.m_axi_bready);
          @(posedge vif.clk);
          vif.m_axi_bvalid <= 1'b0;
        end
      join

      wait (vif.cfg_done);
      trans.display("DRIVER - Transaction Completed");
      no_transactions++;
    end
  endtask
endclass


//=============================================================================
// 5. MONITOR code
//=============================================================================
class monitor;
  virtual dma_intf vif;
  mailbox mon2scb;

  function new(virtual dma_intf vif, mailbox mon2scb);
    this.vif = vif;
    this.mon2scb = mon2scb;
  endfunction

  task main();
    forever begin
      transaction trans;
      trans = new();

      wait (vif.cfg_start);
      trans.src_addr = vif.cfg_src_addr;
      trans.dest_addr = vif.cfg_dest_addr;
      trans.transfer_len = vif.cfg_len;
      trans.payload = new[vif.cfg_len];

      for (int i = 0; i < trans.transfer_len; i++) begin
        wait (vif.m_axi_wvalid && vif.m_axi_wready);
        trans.payload[i] = vif.m_axi_wdata;
        @(posedge vif.clk);
      end

      mon2scb.put(trans);
      trans.display("MONITOR");
    end
  endtask
endclass


//=============================================================================
// 6. SCOREBOARD code
//=============================================================================
class scoreboard;
  mailbox gen2scb; // expected (ground truth from generator)
  mailbox mon2scb; // actual (observed on the AXI write channel)
  int no_transactions;
  int no_errors;

  bit [31:0] golden_mem[bit [31:0]];

  function new(mailbox gen2scb, mailbox mon2scb);
    this.gen2scb = gen2scb;
    this.mon2scb = mon2scb;
  endfunction

  task main();
    transaction expected;
    transaction actual;
    bit match;

    forever begin
      gen2scb.get(expected);
      mon2scb.get(actual);

      if (expected.kind == transaction::WRITE) begin
        // ---- WRITE: update reference memory only, no checking ----
        $display("[SCOREBOARD] WRITE observed @0x%0h, len %0d -> updating reference memory",
                   actual.dest_addr, actual.transfer_len);

        foreach (actual.payload[i])
          golden_mem[actual.dest_addr + i*4] = actual.payload[i];

        actual.display("SCOREBOARD (WRITE - recorded, not checked)");
        no_transactions++;

      end else begin
 
        match = 1'b1;
        $display("[SCOREBOARD] READ verification for addr 0x%0h, len %0d",
                   actual.src_addr, actual.transfer_len);

        if (expected.src_addr !== actual.src_addr) begin
          $error("[SCOREBOARD] [FAIL] SRC_ADDR mismatch. Expected: 0x%0h Actual: 0x%0h",
                   expected.src_addr, actual.src_addr);
          match = 1'b0;
        end

        if (expected.transfer_len !== actual.transfer_len) begin
          $error("[SCOREBOARD] [FAIL] LEN mismatch. Expected: %0d Actual: %0d",
                   expected.transfer_len, actual.transfer_len);
          match = 1'b0;
        end else begin
          foreach (actual.payload[i]) begin
            bit [31:0] addr;
            bit [31:0] golden_data;

            addr = actual.src_addr + i*4;

            if (golden_mem.exists(addr)) begin
              golden_data = golden_mem[addr];
            end else begin
              $error("[SCOREBOARD] [FAIL] Read from address 0x%0h with no prior write on record", addr);
              match = 1'b0;
              golden_data = 'x;
            end

            if (golden_data !== actual.payload[i]) begin
              $error("[SCOREBOARD] [FAIL] Data[%0d] mismatch @0x%0h. Golden: 0x%0h Actual: 0x%0h",
                       i, addr, golden_data, actual.payload[i]);
              match = 1'b0;
            end
          end
        end

        if (match)
          $display("[SCOREBOARD] [SUCCESS] Read data matches reference memory.");
        else
          no_errors++;

        actual.display("SCOREBOARD (READ)");
        no_transactions++;
      end
    end
  endtask
endclass


//=============================================================================
// 7. ENVIRONMENT code
//=============================================================================
class environment;
  generator gen;
  driver driv;
  monitor mon;
  scoreboard scb;

  mailbox gen2driv;
  mailbox gen2scb;
  mailbox mon2scb;

  virtual dma_intf vif;

  function new(virtual dma_intf vif);
    this.vif = vif;
    gen2driv = new();
    gen2scb  = new();
    mon2scb  = new();

    gen  = new(gen2driv, gen2scb);
    driv = new(vif, gen2driv);
    mon  = new(vif, mon2scb);
    scb  = new(gen2scb, mon2scb);
  endfunction

  task pre_test();
    driv.reset();
  endtask

  task test();
    fork
      gen.main();
      driv.main();
      mon.main();
      scb.main();
    join_any
  endtask

  task post_test();
    wait (gen.ended.triggered);
    wait (gen.repeat_count == driv.no_transactions);
    wait (gen.repeat_count == scb.no_transactions);

    $display("=============================================");
    $display(" TEST SUMMARY: %0d/%0d transactions passed",
               scb.no_transactions - scb.no_errors, scb.no_transactions);
    $display(" %s", (scb.no_errors == 0) ? "*** TEST PASSED ***" : "*** TEST FAILED ***");
    $display("=============================================");
  endtask

  task run();
    pre_test();
    test();
    post_test();
    $finish;
  endtask
endclass


//=============================================================================
// 8. TEST code
//=============================================================================
program test(dma_intf i_intf);
  environment env;

  initial begin
    env = new(i_intf);
    env.gen.repeat_count = 10;
    env.run();
  end
endprogram


//=============================================================================
// 9. TESTBENCH code (top)
//=============================================================================
module top;
  bit clk;
  bit rst_n;

  always #5 clk = ~clk;

  initial begin
    clk = 0;
    rst_n = 0;
    #20 rst_n = 1;
  end

  dma_intf i_intf (clk, rst_n);
  test t1 (i_intf);

  dma_controller dut (
    .clk           (i_intf.clk),
    .rst_n         (i_intf.rst_n),
    .cfg_src_addr  (i_intf.cfg_src_addr),
    .cfg_dest_addr (i_intf.cfg_dest_addr),
    .cfg_len       (i_intf.cfg_len),
    .cfg_start     (i_intf.cfg_start),
    .cfg_done      (i_intf.cfg_done),
    .m_axi_araddr  (i_intf.m_axi_araddr),
    .m_axi_arlen   (i_intf.m_axi_arlen),
    .m_axi_arvalid (i_intf.m_axi_arvalid),
    .m_axi_arready (i_intf.m_axi_arready),
    .m_axi_rdata   (i_intf.m_axi_rdata),
    .m_axi_rlast   (i_intf.m_axi_rlast),
    .m_axi_rvalid  (i_intf.m_axi_rvalid),
    .m_axi_rready  (i_intf.m_axi_rready),
    .m_axi_awaddr  (i_intf.m_axi_awaddr),
    .m_axi_awlen   (i_intf.m_axi_awlen),
    .m_axi_awvalid (i_intf.m_axi_awvalid),
    .m_axi_awready (i_intf.m_axi_awready),
    .m_axi_wdata   (i_intf.m_axi_wdata),
    .m_axi_wlast   (i_intf.m_axi_wlast),
    .m_axi_wvalid  (i_intf.m_axi_wvalid),
    .m_axi_wready  (i_intf.m_axi_wready),
    .m_axi_bresp   (i_intf.m_axi_bresp),
    .m_axi_bvalid  (i_intf.m_axi_bvalid),
    .m_axi_bready  (i_intf.m_axi_bready)
  );

  initial begin
    $dumpfile("dma_verification.vcd");
    $dumpvars(0, top);
  end
endmodule
