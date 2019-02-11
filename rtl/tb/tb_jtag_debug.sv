
`define DBG_BASE        32'h1A11_0000

`define DBG_CTRL_REG    15'h0000
`define DBG_HIT_REG     15'h0004
`define DBG_IE_REG      15'h0008
`define DBG_CAUSE_REG   15'h000C
`define DBG_NPC_REG     15'h2000
`define DBG_PPC_REG     15'h2004

int jtag_debug_errors = 0;

task debug_mem_sw;
  input   [31:0] addr;
  input   [31:0] data;
  begin
    dbg_if_soc.write32(addr,1, data, s_tck, s_tms, s_trstn, s_tdi, s_tdo);
    //$display("[DEBUG] Write Mem %x from %x at %t",data, addr, $time);
  end
endtask

task debug_mem_lw;
  input   [31:0] addr;
  output  [31:0] data;
  begin
    dbg_if_soc.read32(addr,1, data, s_tck, s_tms, s_trstn, s_tdi, s_tdo);
    //$display("[DEBUG] Read Mem %x from %x at %t",data, addr, $time);
  end
endtask

task debug_read;
  input   [14:0] addr;
  output  [31:0] data;

  logic [31:0] addr_int;
  begin
    addr_int = `DBG_BASE + addr;
    dbg_if_soc.read32(addr_int,1, data, s_tck, s_tms, s_trstn, s_tdi, s_tdo);
    //$display("[DEBUG] Read %x from %x at %t",data, addr_int, $time);
  end
endtask

task debug_write;
  input   [14:0] addr;
  input   [31:0] data;

  logic [31:0] addr_int;
  begin
    addr_int = `DBG_BASE + addr;
    dbg_if_soc.write32(addr_int,1, data, s_tck, s_tms, s_trstn, s_tdi, s_tdo);
    //$display("[DEBUG] Write %x from %x at %t",data, addr_int, $time);
  end
endtask

task debug_is_stalled;
  output logic is_stalled;
  logic [31:0] data;
  begin
      debug_read(`DBG_CTRL_REG, data);

      is_stalled = data[16];
  end
endtask

task debug_wait_for_stall;
  logic [31:0] data;
  logic        is_stalled;
  begin
    while(1) begin
      debug_is_stalled(is_stalled);

      if (is_stalled)
        break;
    end
    #1us;
  end
endtask

task debug_is_sleeping;
  output logic is_sleeping;
  logic [31:0] data;
  begin
      debug_read(`DBG_HIT_REG, data);

      is_sleeping = data[16];
  end
endtask

task debug_wait_for_sleep;
  logic [31:0] data;
  logic        is_sleeping;
  begin
    while(1) begin
      debug_is_sleeping(is_sleeping);

      if (is_sleeping)
        break;
    end
    #1us;
  end
endtask

task debug_halt;
  logic [31:0] data;
  begin
    debug_read(`DBG_CTRL_REG, data);
    data[16] = 1'b1;
    debug_write(`DBG_CTRL_REG, data);
  end
endtask

task debug_resume;
  logic [31:0] data;
  begin
    debug_read(`DBG_CTRL_REG, data);
    data[16] = 1'b0;
    debug_write(`DBG_CTRL_REG, data);
    #1us;
  end
endtask

task debug_gpr_read;
  input   [ 4:0] addr;
  output  [31:0] data;

  logic   [14:0] addr_int;
  begin
    addr_int = 15'h400 + (addr * 4);
    debug_read(addr_int, data);
  end
endtask

task debug_gpr_write;
  input   [ 4:0] addr;
  input   [31:0] data;

  logic   [14:0] addr_int;
  begin
    addr_int = 15'h400 + (addr * 4);
    debug_write(addr_int, data);
  end
endtask

task debug_csr_read;
  input   [11:0] addr;
  output  [31:0] data;

  logic   [14:0] addr_int;
  begin
    addr_int = 15'h4000 + (addr * 4);
    debug_read(addr_int, data);
  end
endtask

task debug_csr_write;
  input   [11:0] addr;
  input   [31:0] data;

  logic   [14:0] addr_int;
  begin
    addr_int = 15'h4000 + (addr * 4);
    debug_write(addr_int, data);
  end
endtask

task debug_print_perf;
  logic [31:0] data;
  logic [11:0] addr;
  int i;
  begin
    for(i = 0; i < 11; i++) begin
      addr = 12'h780 + i;
      debug_csr_read(addr, data);
      $display("CSR %X: %X", addr, data);
    end
  end
endtask

//------------------------------------------------------------------------------
// Actual test cases
// Have to be aligned with program running on core
//------------------------------------------------------------------------------
  logic [31: 0] dbg_testcase_addr;
  logic [31: 0] dbg_tb_errors_addr;
  logic [31: 0] dbg_tb_errors;
  logic [31: 0] dbg_tb_irq_trig_addr;

  task debug_test_init;
    begin
      #2000us

      debug_wait_for_stall();

      $display("[DEBUG] Test Init");
      dbg_tb_errors = 0;
      debug_halt();
      debug_write(`DBG_IE_REG, 32'h0000000F);
      debug_gpr_write(15,  32'h01);

      debug_wait_for_stall();
      debug_resume();

      debug_wait_for_stall();
      debug_gpr_read(14, dbg_testcase_addr);
      debug_gpr_read(15, dbg_tb_errors_addr);

      debug_resume();
    end
  endtask

  task debug_test_finish;
    begin
      $display("[DEBUG] Test Finish");
      debug_wait_for_stall();
      debug_mem_sw(dbg_tb_errors_addr, dbg_tb_errors);
      debug_resume();
    end
  endtask

  task debug_test_rw_gpr;
    logic [31:0] data;
    int i;
    begin
      $display("[DEBUG] Running test_rw_gpr");
      debug_wait_for_stall();

      // read all of them, although we don't really care here
      for(i = 0; i < 32; i++) begin
        debug_gpr_read(i, data);
        //$display("GPR %d: %X", i, data);
      end

      // now check some specific ones for known values
      debug_gpr_read(5, data);
      if (data !== 32'h5555_5555) begin
        $display("ERROR: x5 is not 0x55555555, but %X", data);
        dbg_tb_errors++;
      end

      debug_gpr_read(6, data);
      if (data !== 32'h1234_5666) begin
        $display("ERROR: x6 is not 0x12345666, but %X", data);
        dbg_tb_errors++;
      end

      debug_gpr_read(7, data);
      if (data !== 32'h0000_0077) begin
        $display("ERROR: x7 is not 0x00000077, but %X", data);
        dbg_tb_errors++;
      end

      debug_gpr_read(8, data);
      if (data !== 32'h0000_0088) begin
        $display("ERROR: x8 is not 0x00000088, but %X", data);
        dbg_tb_errors++;
      end

      debug_gpr_read(15, data);
      if (data !== 32'h0000_0031) begin
        $display("ERROR: x15 is not 0x00000031, but %X", data);
        dbg_tb_errors++;
      end

      debug_resume();
      debug_wait_for_stall();

      // and finally write some stuff to the GPRs
      debug_gpr_write(5,  32'h5432_1089);
      debug_gpr_write(6,  32'h1122_3344);
      debug_gpr_write(15, 32'hFEDC_BA09);

      debug_resume();
    end
  endtask

  task debug_test_rw_csr;
    logic [31:0] data;
    int i;
    begin
      $display("[DEBUG] Running test_rw_csr");
      debug_wait_for_stall();

      // now check some specific ones for known values
      debug_csr_read(15'h300, data);
      if (data !== 32'h0000_1800) begin
        $display("ERROR: mstatus is not 0x0000_1800, but %X", data);
        dbg_tb_errors++;
      end

      debug_csr_read(15'h341, data);
      if (data !== 32'h1234_5678) begin
        $display("ERROR: mstatus is not 0x1234_5678, but %X", data);
        dbg_tb_errors++;
      end


      debug_resume();
      debug_wait_for_stall();

      // and finally write some stuff to the CSRs
      debug_csr_write(15'h300, 32'h0000_0080);
      debug_csr_write(15'h341, 32'h8765_4321);

      debug_resume();
    end
  endtask

  task debug_test_rw_dbg_regs;
    logic [31:0] dbg_ctrl;
    logic [31:0] dbg_ie;
    logic [31:0] data;
    int i;
    begin
      $display("[DEBUG] Running test_rw_dbg_regs");
      debug_wait_for_stall();

      // lets first read out all registers and store them, so we can restore
      // them later
      debug_read(`DBG_CTRL_REG, dbg_ctrl);
      debug_read(`DBG_IE_REG,   dbg_ie);


      // now we write our own values and check them later
      debug_write(`DBG_CTRL_REG, 32'h0001_0001);
      debug_write(`DBG_IE_REG,   32'h0000_08AC);

      // now check some specific ones for known values
      debug_read(`DBG_CTRL_REG, data);
      if (data !== 32'h0001_0001) begin
        $display("ERROR: DBG_CTRL is not 0x0000_0001, but %X", data);
        dbg_tb_errors++;
      end

      debug_read(`DBG_IE_REG, data);
      if (data !== 32'h0000_08AC) begin
        $display("ERROR: DBG_IE is not 0x0000_08AC, but %X", data);
        dbg_tb_errors++;
      end


      // now restore everything
      debug_write(`DBG_CTRL_REG,  dbg_ctrl);
      debug_write(`DBG_IE_REG,    dbg_ie);

      debug_resume();
    end
  endtask

  task debug_test_halt_resume;
    logic [31:0] addr_changeme;
    logic [31:0] npc;
    logic [31:0] ppc;
    logic        is_stalled;
    int i;
    begin
      $display("[DEBUG] Running test_halt_resume");
      debug_wait_for_stall();

      // get the address of changeme to break the loop later
      debug_gpr_read(5'd14, addr_changeme);


      debug_resume();

      for(i = 0; i < 10; i++) begin
        debug_halt();

        debug_wait_for_stall();
        // read NPC and PPC
        debug_read(`DBG_NPC_REG, npc);
        debug_read(`DBG_PPC_REG, ppc);

        if ($signed(npc - ppc) >= 0) begin
          if ((npc - ppc) > 32'h40) begin
            $display("ERROR: NPC and PPC are far apart");
            dbg_tb_errors++;
          end
        end else begin
          if ((ppc - npc) > 32'h40) begin
            $display("ERROR: NPC and PPC are far apart");
            dbg_tb_errors++;
          end
        end

        debug_resume();

        // check if the core is indeed running
        debug_is_stalled(is_stalled);
        if (is_stalled) begin
            $display("ERROR: Core is still stalled");
            dbg_tb_errors++;
        end
      end

      debug_halt();
      debug_mem_sw(addr_changeme, 32'h0);
      debug_resume();

      debug_wait_for_stall();
      debug_resume();
    end
  endtask
  task debug_test_ebreak;
    logic [31:0] npc, npc_last;
    logic [31:0] ppc, ppc_last;
    logic [31:0] dbg_cause;
    int i;
    begin
      $display("[DEBUG] Running test_ebreak");

      debug_wait_for_stall();
      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      for(i = 0; i < 10; i++) begin
        debug_wait_for_stall();
        // read NPC and PPC
        debug_read(`DBG_NPC_REG, npc);
        debug_read(`DBG_PPC_REG, ppc);

        if ((npc - ppc) !== 32'h4 && (npc - ppc) !== 32'h2) begin
          $display("ERROR: NPC and PPC are not 2 or 4 apart");
          dbg_tb_errors++;
        end

        if (i != 0 && ppc !== npc_last) begin
          $display("ERROR: PPC is not equal to last NPC");
          dbg_tb_errors++;
        end

        // check DBG_CAUSE
        debug_read(`DBG_CAUSE_REG, dbg_cause);

        if (dbg_cause !== 32'h0000_0003) begin
          $display("ERROR: CAUSE is not equal to BP");
          dbg_tb_errors++;
        end

        npc_last = npc;
        ppc_last = ppc;

        debug_resume();
      end
    end
  endtask

  task debug_test_npc_ppc;
    logic [31:0] npc;
    logic [31:0] ppc;
    logic [31:0] npc_exp;
    logic [31:0] ppc_exp;
    logic [31:0] npc_new;
    logic [31:0] data;
    begin
      $display("[DEBUG] Running test_npc_ppc");

      debug_wait_for_stall();
      debug_write(`DBG_IE_REG, 32'h0000_08AC);
      debug_resume();

      debug_wait_for_stall();
      // read NPC and PPC
      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      debug_gpr_read(5'd13, ppc_exp);
      debug_gpr_read(5'd14, npc_exp);
      debug_gpr_read(5'd15, npc_new);

      if (npc !== npc_exp) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, npc_exp);
        dbg_tb_errors++;
      end

      if (ppc !== ppc_exp) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, ppc_exp);
        dbg_tb_errors++;
      end

      debug_read(`DBG_CAUSE_REG, data);
      if (data !== 32'h0000_000B) begin
        $display("ERROR: DBG_CAUSE has not the correct value: act %X, expected %X", data, 32'h0000_00B);
        dbg_tb_errors++;
      end

      // now jump to the next instruction
      debug_write(`DBG_NPC_REG, npc_new);

      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      if (npc !== npc_new) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, npc_new);
        dbg_tb_errors++;
      end

      if (ppc !== ppc_exp) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, ppc_exp);
        dbg_tb_errors++;
      end

      debug_resume();
    end
  endtask

  task debug_test_illegal;
    logic [31:0] npc;
    logic [31:0] ppc;
    logic [31:0] npc_exp;
    logic [31:0] ppc_exp;
    logic [31:0] npc_new;
    logic [31:0] data;
    begin
      $display("[DEBUG] Running test_illegal");

      debug_wait_for_stall();
      debug_write(`DBG_IE_REG, 32'h0000_08AC);
      debug_resume();

      debug_wait_for_stall();
      // read NPC and PPC
      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      debug_gpr_read(5'd13, ppc_exp);
      debug_gpr_read(5'd14, npc_exp);
      debug_gpr_read(5'd15, npc_new);

      if (npc !== npc_exp) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, npc_exp);
        dbg_tb_errors++;
      end

      if (ppc !== ppc_exp) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, ppc_exp);
        dbg_tb_errors++;
      end

      debug_read(`DBG_CAUSE_REG, data);
      if (data !== 32'h0000_0002) begin
        $display("ERROR: DBG_CAUSE has not the correct value: act %X, expected %X", data, 32'h0000_002);
        dbg_tb_errors++;
      end

      // now jump to the next instruction
      debug_write(`DBG_NPC_REG, npc_new);

      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      if (npc !== npc_new) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, npc_new);
        dbg_tb_errors++;
      end

      if (ppc !== ppc_exp) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, ppc_exp);
        dbg_tb_errors++;
      end

      debug_resume();
    end
  endtask

  task debug_test_single_step;
    logic [31:0] npc;
    logic [31:0] ppc;
    logic [31:0] npc_last;
    logic [31:0] ppc_last;
    logic [31:0] data;
    int i;
    begin
      $display("[DEBUG] Running test_single_step");

      debug_wait_for_stall();
      debug_read(`DBG_NPC_REG, npc_last);
      debug_read(`DBG_PPC_REG, ppc_last);

      debug_read(`DBG_HIT_REG, data);
      if (data[0]) begin
        $display("ERROR: SSTH is set");
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      for(i = 0; i < 4; i++) begin
        debug_wait_for_stall();
        // read NPC and PPC
        debug_read(`DBG_NPC_REG, npc);
        debug_read(`DBG_PPC_REG, ppc);

        if (ppc !== npc_last) begin
          $display("ERROR: PPC is not equal to last NPC: act %X, expected %X", ppc, npc_last);
          dbg_tb_errors++;
        end

        debug_read(`DBG_HIT_REG, data);
        if (~data[0]) begin
          $display("ERROR: SSTH is not set");
          dbg_tb_errors++;
        end

        npc_last = npc;
        ppc_last = ppc;

        debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      end

      debug_write(`DBG_CTRL_REG, 32'h0000_0000); // RESUME, and no Single Step

      //--------------------------------------------------------------------------
      // now the tight branch loop with 2 instructions
      //--------------------------------------------------------------------------
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step

      // do a couple to make sure we are inside the loop
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_read(`DBG_NPC_REG, npc_last);
      debug_read(`DBG_PPC_REG, ppc_last);
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      for(i = 0; i < 100; i++) begin
        debug_wait_for_stall();
        // read NPC and PPC
        debug_read(`DBG_NPC_REG, npc);
        debug_read(`DBG_PPC_REG, ppc);

        if (ppc !== npc_last) begin
          $display("ERROR: PPC is not equal to last NPC: act %X, expected %X", ppc, npc_last);
          dbg_tb_errors++;
        end

        debug_read(`DBG_HIT_REG, data);
        if (~data[0]) begin
          $display("ERROR: SSTH is not set");
          dbg_tb_errors++;
        end

        npc_last = npc;
        ppc_last = ppc;

        debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      end

      debug_gpr_read(5'd14, data);
      debug_mem_sw(data, 32'h0);
      debug_write(`DBG_CTRL_REG, 32'h0000_0000); // RESUME, and no Single Step

      //--------------------------------------------------------------------------
      // now the tight loop with 1 instruction (branch)
      //--------------------------------------------------------------------------
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step

      // do a couple to make sure we are inside the loop
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_read(`DBG_NPC_REG, npc_last);
      debug_read(`DBG_PPC_REG, ppc_last);
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      for(i = 0; i < 100; i++) begin
        debug_wait_for_stall();
        // read NPC and PPC
        debug_read(`DBG_NPC_REG, npc);
        debug_read(`DBG_PPC_REG, ppc);

        if (ppc !== ppc_last) begin
          $display("ERROR: PPC is not equal to last PPC: act %X, expected %X", ppc, ppc_last);
          dbg_tb_errors++;
        end

        if (npc !== npc_last) begin
          $display("ERROR: NPC is not equal to last NPC: act %X, expected %X", npc, npc_last);
          dbg_tb_errors++;
        end

        debug_read(`DBG_HIT_REG, data);
        if (~data[0]) begin
          $display("ERROR: SSTH is not set");
          dbg_tb_errors++;
        end

        npc_last = npc;
        ppc_last = ppc;

        debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      end

      debug_wait_for_stall();
      debug_gpr_read(5'd14, data);
      debug_write(`DBG_NPC_REG, data);
      debug_write(`DBG_CTRL_REG, 32'h0000_0000); // RESUME, and no Single Step

      //--------------------------------------------------------------------------
      // now the tight loop with 1 instruction (jump)
      //--------------------------------------------------------------------------
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step

      // do a couple to make sure we are inside the loop
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();
      debug_read(`DBG_NPC_REG, npc_last);
      debug_read(`DBG_PPC_REG, ppc_last);
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      for(i = 0; i < 100; i++) begin
        debug_wait_for_stall();
        // read NPC and PPC
        debug_read(`DBG_NPC_REG, npc);
        debug_read(`DBG_PPC_REG, ppc);

        if (ppc !== ppc_last) begin
          $display("ERROR: PPC is not equal to last PPC: act %X, expected %X", ppc, ppc_last);
          dbg_tb_errors++;
        end

        if (npc !== npc_last) begin
          $display("ERROR: NPC is not equal to last NPC: act %X, expected %X", npc, npc_last);
          dbg_tb_errors++;
        end

        debug_read(`DBG_HIT_REG, data);
        if (~data[0]) begin
          $display("ERROR: SSTH is not set");
          dbg_tb_errors++;
        end

        npc_last = npc;
        ppc_last = ppc;

        debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      end

      debug_wait_for_stall();
      debug_gpr_read(5'd15, data);
      debug_write(`DBG_NPC_REG, data);
      debug_write(`DBG_CTRL_REG, 32'h0000_0000); // RESUME, and no Single Step

      //--------------------------------------------------------------------------
      // now the tight loop with 1 instruction (ecall)
      //--------------------------------------------------------------------------
      debug_wait_for_stall();
      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step
      debug_gpr_read(5'd15, npc_last);
      debug_gpr_read(5'd14, ppc_last);

      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      debug_wait_for_stall();

      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      if (ppc !== ppc_last) begin
        $display("ERROR: a) PPC is not equal to last PPC: act %X, expected %X", ppc, ppc_last);
        dbg_tb_errors++;
      end

      if (npc !== npc_last) begin
        $display("ERROR: a) NPC is not equal to last PPC: act %X, expected %X", npc, npc_last);
        dbg_tb_errors++;
      end

      debug_write(`DBG_NPC_REG, ppc);

      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      for(i = 0; i < 100; i++) begin
        debug_wait_for_stall();
        // read NPC and PPC
        debug_read(`DBG_NPC_REG, npc);
        debug_read(`DBG_PPC_REG, ppc);

        if (ppc !== ppc_last) begin
          $display("ERROR: PPC is not equal to last PPC: act %X, expected %X", ppc, ppc_last);
          dbg_tb_errors++;
        end

        if (npc !== npc_last) begin
          $display("ERROR: NPC is not equal to last NPC: act %X, expected %X", npc, npc_last);
          dbg_tb_errors++;
        end

        debug_read(`DBG_HIT_REG, data);
        if (~data[0]) begin
          $display("ERROR: SSTH is not set");
          dbg_tb_errors++;
        end

        debug_write(`DBG_NPC_REG, ppc);

        debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step
      end

      debug_wait_for_stall();
      debug_gpr_read(5'd13, data);
      debug_write(`DBG_NPC_REG, data);
      debug_write(`DBG_CTRL_REG, 32'h0000_0000); // RESUME, and no Single Step

    end
  endtask

  task debug_test_jumps;
    logic [31:0] data;
    logic [31:0] ppc;
    begin
      $display("[DEBUG] Running test_jumps");

      debug_wait_for_stall();
      debug_gpr_read(5'd15, data);
      debug_write(`DBG_NPC_REG, data);
      debug_write(`DBG_CTRL_REG, 32'h0000_0000); // RESUME

      debug_wait_for_stall();


      // jump to ebreak
      debug_wait_for_stall();
      debug_gpr_read(5'd15, data);
      debug_write(`DBG_NPC_REG, data);
      debug_write(`DBG_CTRL_REG, 32'h0000_0000); // RESUME

      debug_wait_for_stall();

      debug_read(`DBG_PPC_REG, ppc);
      if (ppc !== data) begin
        $display("ERROR: PPC is not equal to jump instruction: act %X, expected %X", ppc, data);
        dbg_tb_errors++;
      end

      debug_resume();
    end
  endtask

  task debug_test_jumps_after_branch;
    logic [31:0] npc;
    logic [31:0] ppc;
    logic [31:0] pc0;
    logic [31:0] pc1;
    logic [31:0] pc2;
    logic [31:0] bt;
    logic [31:0] jmp;
    begin
      $display("[DEBUG] Running test_jumps_after_branch");

      debug_wait_for_stall();

      debug_gpr_read(5'd12, bt);
      debug_gpr_read(5'd13, jmp);
      debug_gpr_read(5'd14, pc0);
      debug_gpr_read(5'd15, pc1);

      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step

      // look for pc0, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc0) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc0);
        dbg_tb_errors++;
      end
      if (npc !== pc1) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc1);
        dbg_tb_errors++;
      end

      // look for pc1, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc1) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc1);
        dbg_tb_errors++;
      end
      if (npc !== bt) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, bt);
        dbg_tb_errors++;
      end

      // look for bt, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== bt) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, bt);
        dbg_tb_errors++;
      end
      if (npc !== jmp) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, jmp);
        dbg_tb_errors++;
      end

      // look for jmp, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);

      if (ppc !== jmp) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, jmp);
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0001_0000); // disable single step

      debug_resume();



      //------------------------------------------------------------------------------
      debug_wait_for_stall();

      debug_gpr_read(5'd12, pc2);
      debug_gpr_read(5'd13, jmp);
      debug_gpr_read(5'd14, pc0);
      debug_gpr_read(5'd15, pc1);

      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step

      // look for pc0, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc0) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc0);
        dbg_tb_errors++;
      end
      if (npc !== pc1) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc1);
        dbg_tb_errors++;
      end

      // look for pc1, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc1) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc1);
        dbg_tb_errors++;
      end
      if (npc !== pc2) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc2);
        dbg_tb_errors++;
      end

      // look for pc2, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc2) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc2);
        dbg_tb_errors++;
      end
      if (npc !== jmp) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, jmp);
        dbg_tb_errors++;
      end

      // look for jmp, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);

      if (ppc !== jmp) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, jmp);
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0001_0000); // disable single step

      debug_resume();
    end
  endtask

  task debug_test_branch;
    logic [31:0] npc;
    logic [31:0] ppc;
    logic [31:0] pc0;
    logic [31:0] pc1;
    logic [31:0] pc2;
    logic [31:0] pc3;
    int i;
    begin
      $display("[DEBUG] Running test_branch");

      // TAKEN TOWARD
      debug_wait_for_stall();

      debug_gpr_read(5'd12, pc0);
      debug_gpr_read(5'd13, pc1);
      debug_gpr_read(5'd14, pc2);
      debug_gpr_read(5'd15, pc3);

      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step

      // look for pc0, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc0) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc0);
        dbg_tb_errors++;
      end
      if (npc !== pc1) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc1);
        dbg_tb_errors++;
      end

      // look for pc1, the beq
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc1) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc1);
        dbg_tb_errors++;
      end
      if (npc !== pc2) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc2);
        dbg_tb_errors++;
      end

      // look for pc2, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc2) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc2);
        dbg_tb_errors++;
      end
      if (npc !== pc3) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc3);
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0001_0000); // disable single step

      debug_resume();

      // NOT TAKEN TOWARD
      debug_wait_for_stall();

      debug_gpr_read(5'd12, pc0);
      debug_gpr_read(5'd13, pc1);
      debug_gpr_read(5'd14, pc2);
      debug_gpr_read(5'd15, pc3);

      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step

      // look for pc0, the bne
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc0) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc0);
        dbg_tb_errors++;
      end
      if (npc !== pc1) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc1);
        dbg_tb_errors++;
      end

      // look for pc1, the j
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc1) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc1);
        dbg_tb_errors++;
      end
      if (npc !== pc3) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc3);
        dbg_tb_errors++;
      end

      // look for pc3, the nop
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);

      if (ppc !== pc3) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc3);
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0001_0000); // disable single step

      debug_resume();

      // TAKEN BACKWARD
      debug_wait_for_stall();

      debug_gpr_read(5'd12, pc0);
      debug_gpr_read(5'd13, pc1);
      debug_gpr_read(5'd14, pc2);
      debug_gpr_read(5'd15, pc3);

      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step
      debug_resume();

      for (i = 0; i < 10-1; i++) begin

          // look for pc0, the addi
          debug_wait_for_stall();
          // read NPC and PPC
          debug_read(`DBG_PPC_REG, ppc);
          debug_read(`DBG_NPC_REG, npc);
          if (ppc !== pc0) begin
            $display("ERROR 0: PPC has not the correct value: act %X, expected %X", ppc, pc0);
            dbg_tb_errors++;
          end
          if (npc !== pc1) begin
            $display("ERROR 0: NPC has not the correct value: act %X, expected %X", npc, pc1);
            dbg_tb_errors++;
          end

          debug_resume();

          // look for pc1, the bne
          debug_wait_for_stall();
          // read NPC and PPC
          debug_read(`DBG_PPC_REG, ppc);
          debug_read(`DBG_NPC_REG, npc);
          if (ppc !== pc1) begin
            $display("ERROR 1: PPC has not the correct value: act %X, expected %X", ppc, pc1);
            dbg_tb_errors++;
          end
          if (npc !== pc0) begin
            $display("ERROR 1: NPC has not the correct value: act %X, expected %X", npc, pc0);
            dbg_tb_errors++;
          end
          debug_resume();
      end
      //last iteration

      // look for pc0, the addi
      debug_wait_for_stall();
      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);
      if (ppc !== pc0) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc0);
        dbg_tb_errors++;
      end
      if (npc !== pc1) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc1);
        dbg_tb_errors++;
      end

      debug_resume();

      // look for pc1, the beq
      debug_wait_for_stall();
      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);
      if (ppc !== pc1) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc1);
        dbg_tb_errors++;
      end
      if (npc !== pc2) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc2);
        dbg_tb_errors++;
      end
      debug_resume();

      // look for pc2, the jump
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);
      if (ppc !== pc2) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc2);
        dbg_tb_errors++;
      end
      if (npc !== pc3) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc3);
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0001_0000); // disable single step

      debug_resume();

      // NOT TAKEN BACKWARD
      debug_wait_for_stall();

      debug_gpr_read(5'd12, pc0);
      debug_gpr_read(5'd13, pc1);
      debug_gpr_read(5'd14, pc2);
      debug_gpr_read(5'd15, pc3);

      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step

      // look for pc0, the addi
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc0) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc0);
        dbg_tb_errors++;
      end
      if (npc !== pc1) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc1);
        dbg_tb_errors++;
      end

      // look for pc1, the beq
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc1) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc1);
        dbg_tb_errors++;
      end
      if (npc !== pc2) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc2);
        dbg_tb_errors++;
      end

      // look for pc3, the j
      debug_resume();
      debug_wait_for_stall();

      // read NPC and PPC
      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      if (ppc !== pc2) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, pc1);
        dbg_tb_errors++;
      end
      if (npc !== pc3) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, pc3);
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0001_0000); // disable single step

      debug_resume();

    end
  endtask

  task debug_test_wfi_sleep;
    logic [31:0] npc;
    logic [31:0] ppc;
    logic [31:0] npc_exp_1, npc_exp_2, npc_exp_3, npc_exp_4;
    logic [31:0] ppc_exp;
    logic [31:0] jmp_to;
    logic [31:0] data;
    int i;
    begin
      $display("[DEBUG] Running debug_test_wfi_sleep");

      // WFI
      debug_wait_for_stall();

      debug_gpr_read(5'd13, ppc_exp);
      debug_gpr_read(5'd14, npc_exp_1);
      debug_gpr_read(5'd15, npc_exp_2);

      debug_read(`DBG_HIT_REG, data);
      if (data[0]) begin
        $display("ERROR: SSTH is set");
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      debug_wait_for_stall(); //wfi

      // read NPC and PPC
      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      if (npc !== npc_exp_1) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, npc_exp_1);
        dbg_tb_errors++;
      end

      if (ppc !== ppc_exp) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, ppc_exp);
        dbg_tb_errors++;
      end

      debug_read(`DBG_HIT_REG, data);
      if (~data[0]) begin
        $display("ERROR: SSTH is not set");
        dbg_tb_errors++;
      end
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      debug_wait_for_stall(); //addi

      // read NPC and PPC
      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      if (npc !== npc_exp_2) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, npc_exp_2);
        dbg_tb_errors++;
      end

      if (ppc !== npc_exp_1) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, npc_exp_1);
        dbg_tb_errors++;
      end

      debug_read(`DBG_HIT_REG, data);
      if (~data[0]) begin
        $display("ERROR: SSTH is not set");
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0000_0000); //RESUME, but NO Single Step

      //------------------------------------------------------------------------------
      // SLEEP SINGLE STEP, the CORE won't go to sleep
      //------------------------------------------------------------------------------
      debug_wait_for_stall(); //ebreak
      debug_gpr_read(5'd11, ppc_exp);
      debug_gpr_read(5'd12, npc_exp_1);
      debug_gpr_read(5'd13, npc_exp_2);
      debug_gpr_read(5'd14, npc_exp_3);

      jmp_to = npc_exp_2;

      debug_write(`DBG_CTRL_REG, 32'h0001_0001); // set single-step
      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      debug_wait_for_stall(); //wfi
      // read NPC and PPC
      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);


      if (npc !== npc_exp_1) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, npc_exp_1);
        dbg_tb_errors++;
      end

      if (ppc !== ppc_exp) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, ppc_exp);
        dbg_tb_errors++;
      end

      debug_read(`DBG_HIT_REG, data);
      if (~data[0]) begin
        $display("ERROR: SSTH is not set");
        dbg_tb_errors++;
      end

      debug_write(`DBG_NPC_REG, jmp_to);

      debug_write(`DBG_CTRL_REG, 32'h0000_0001); // RESUME, but Single Step

      debug_wait_for_stall(); //second addi
      // read NPC and PPC
      debug_read(`DBG_NPC_REG, npc);
      debug_read(`DBG_PPC_REG, ppc);

      if (ppc !== jmp_to) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, jmp_to);
        dbg_tb_errors++;
      end

      if (npc !== npc_exp_3) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, npc_exp_3);
        dbg_tb_errors++;
      end


      debug_read(`DBG_HIT_REG, data);
      if (~data[0]) begin
        $display("ERROR: SSTH is not set");
        dbg_tb_errors++;
      end

      debug_write(`DBG_CTRL_REG, 32'h0000_0000); // RESUME, but NO Single Step

    end
  endtask

 task debug_test_access_while_sleep;
    logic [31:0] data;
    logic [31:0] ppc;
    logic [31:0] npc;
    logic        is_sleeping;
    int i;
    begin
      $display("[DEBUG] Running debug_test_access_while_sleep");

      debug_wait_for_stall();
      debug_resume();

      //meanwhile the core is going to sleep. It should be faster than this check
      debug_is_sleeping(is_sleeping);
      if (~is_sleeping) begin
          $display("ERROR: Core is still awake");
          dbg_tb_errors++;
      end
      debug_halt();

      debug_read(`DBG_PPC_REG, ppc);
      debug_read(`DBG_NPC_REG, npc);

      debug_gpr_read(5'd12, data);
      if (data !== 32'h16161616) begin
        $display("ERROR: x13 has not the correct value: act %X, expected %X", data, 32'h16161616);
        dbg_tb_errors++;
      end

      debug_gpr_read(5'd13, data);
      if (data !== 32'h17171717) begin
        $display("ERROR: x17 has not the correct value: act %X, expected %X", data, 32'h17171717);
        dbg_tb_errors++;
      end

      debug_csr_read(12'h780, data);
      if (data !== 32'hB15B_00B5) begin
        $display("ERROR: CSR 0xF01 has not the correct value: act %X, expected %X", data, 32'hB15B_00B5);
        dbg_tb_errors++;
      end

      debug_gpr_write(5'd13,   32'hFEDCBA00);
      debug_csr_write(12'h780, 32'hC0DE1234);

      debug_gpr_read(5'd15, data);
      if (data !== ppc) begin
        $display("ERROR: PPC has not the correct value: act %X, expected %X", ppc, data);
        dbg_tb_errors++;
      end

      // wake-up core, a continue is enough
      debug_resume();


      //------------------------------------------------------------------------------
      // now a second time with setting the NPC
      //------------------------------------------------------------------------------
      debug_wait_for_stall();
      debug_resume();

      //meanwhile the core is going to sleep
      debug_wait_for_sleep();
      debug_halt();

      debug_gpr_write(5'd13,   32'hFEDCBA00);
      debug_csr_write(12'h780, 32'hC0DE1234);

      debug_gpr_read(5'd15, data);
      debug_write(`DBG_NPC_REG, data);
      debug_read(`DBG_NPC_REG, npc);
      if (npc !== data) begin
        $display("ERROR: NPC has not the correct value: act %X, expected %X", npc, data);
        dbg_tb_errors++;
      end

      debug_resume();
    end
  endtask


  task debug_tests;
    logic [31:0] testcase_nr;
    begin
      debug_test_init();

      while(1) begin
        debug_wait_for_stall();
        debug_mem_lw(dbg_testcase_addr, testcase_nr);

        unique case (testcase_nr)
          02: debug_test_rw_gpr();
          03: debug_test_rw_csr();
          04: debug_test_rw_dbg_regs();
          05: debug_test_halt_resume();
          06: debug_test_ebreak();
          07: debug_test_npc_ppc();
          08: debug_test_illegal();
          09: debug_test_single_step();
          10: debug_test_jumps();
          11: debug_test_jumps_after_branch();
          12: debug_test_branch();
          13: debug_test_wfi_sleep();
          14: debug_test_access_while_sleep();

          32'hFFFF_FFFF: break;
          default: $display("ERROR: Unknown testcase %d", testcase_nr);
        endcase
      end

      debug_test_finish();
    end
  endtask