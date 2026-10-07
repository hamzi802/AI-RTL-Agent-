// tb_sync_fifo.sv
// Self-checking testbench for sync_fifo
// Author: Rumali Siddiqua
//
// Run with Icarus 12:  iverilog -g2012 tb_sync_fifo.sv <dut>.sv
// or just use scripts/run_tb.sh
//
// Plusargs: +SEED=n +RAND_CYCLES=n +MAX_ERR_PRINT=n +DUMP (wave.vcd)
// Params:   -P tb_sync_fifo.DATA_WIDTH=n -P tb_sync_fifo.DEPTH=n
//
// Inputs are driven on negedge. A small model of the FIFO runs next to the
// DUT and outputs are compared after every posedge, and again right after the
// inputs change (to catch combinational paths, spec says there shouldn't be any).
// Last line printed is always TEST_RESULT: PASS or FAIL.
`timescale 1ns/1ps

module tb_sync_fifo;

  parameter int DATA_WIDTH = 8;
  parameter int DEPTH      = 16;
  localparam int CNT_W     = $clog2(DEPTH) + 1;

  // DUT signals
  logic                  clk = 1'b0;
  logic                  rst_n;
  logic                  wr_en;
  logic [DATA_WIDTH-1:0] wr_data;
  logic                  rd_en;
  logic [DATA_WIDTH-1:0] rd_data;
  logic                  full;
  logic                  empty;
  logic [CNT_W-1:0]      count;

  sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .wr_data(wr_data),
    .rd_en(rd_en), .rd_data(rd_data),
    .full(full), .empty(empty), .count(count)
  );

  always #5 clk = ~clk;

  // reference model
  logic [DATA_WIDTH-1:0] m_mem [0:DEPTH-1];
  integer                m_wp, m_rp, m_cnt;
  logic [DATA_WIDTH-1:0] m_rd;


  string  test_name;
  integer cycle_n      = 0;
  integer n_checks     = 0;
  integer n_errors     = 0;
  integer max_err_print = 25;
  integer n_tests      = 0;
  logic   checking     = 1'b0;   // outputs are X before first reset
  integer seed         = 1;
  integer rand_cycles  = 5000;

  // coverage counters, all have to be > 0 at the end
  integer cov_full        = 0;
  integer cov_empty_again = 0;   // went back to empty after having data
  integer cov_overflow    = 0;   // wr_en while full
  integer cov_underflow   = 0;   // rd_en while empty
  integer cov_rw_empty    = 0;
  integer cov_rw_full     = 0;
  integer cov_rw_mid      = 0;
  integer cov_wrap        = 0;   // write ptr wrapped
  integer cov_reset_mid   = 0;   // reset while not empty

  // update the model with the inputs that were there at the posedge
  task automatic model_step(input logic rn, input logic we,
                            input logic [DATA_WIDTH-1:0] wd, input logic re);
    logic dw, dr;
    begin
      if (!rn) begin
        if (m_cnt > 0) cov_reset_mid++;
        m_wp = 0; m_rp = 0; m_cnt = 0; m_rd = '0;
      end else begin
        dw = we && (m_cnt < DEPTH);
        dr = re && (m_cnt > 0);
        if (we && m_cnt == DEPTH)                 cov_overflow++;
        if (re && m_cnt == 0)                     cov_underflow++;
        if (we && re && m_cnt == 0)               cov_rw_empty++;
        if (we && re && m_cnt == DEPTH)           cov_rw_full++;
        if (we && re && m_cnt > 0 && m_cnt < DEPTH) cov_rw_mid++;
        if (dw && m_wp == DEPTH-1)                cov_wrap++;
        if (dr && !dw && m_cnt == 1)              cov_empty_again++;
        if (dw && !dr && m_cnt == DEPTH-1)        cov_full++;
        // rd and wr can't hit the same slot here (read blocked when empty, write blocked when full)
        if (dr) begin m_rd = m_mem[m_rp]; m_rp = (m_rp + 1) % DEPTH; end
        if (dw) begin m_mem[m_wp] = wd;   m_wp = (m_wp + 1) % DEPTH; end
        m_cnt = m_cnt + (dw ? 1 : 0) - (dr ? 1 : 0);
      end
    end
  endtask

  // print one ERROR line per mismatch
  task automatic report(input string phase, input string sig,
                        input logic [63:0] exp_v, input logic [63:0] got_v);
    begin
      n_errors++;
      if (n_errors <= max_err_print)
        $display("ERROR test=%s cycle=%0d phase=%s signal=%s expected=0x%0h got=0x%0h | inputs: rst_n=%b wr_en=%b wr_data=0x%0h rd_en=%b | model: count=%0d",
                 test_name, cycle_n, phase, sig, exp_v, got_v,
                 rst_n, wr_en, wr_data, rd_en, m_cnt);
      else if (n_errors == max_err_print + 1)
        $display("NOTE  further ERROR lines suppressed (+MAX_ERR_PRINT=%0d)", max_err_print);
    end
  endtask

  task automatic check(input string phase);
    begin
      if (checking) begin
        n_checks++;
        if (count !== m_cnt[CNT_W-1:0])       report(phase, "count", m_cnt, count);
        if (empty !== (m_cnt == 0))           report(phase, "empty", (m_cnt == 0), empty);
        if (full  !== (m_cnt == DEPTH))       report(phase, "full",  (m_cnt == DEPTH), full);
        if (rd_data !== m_rd)                 report(phase, "rd_data", m_rd, rd_data);
      end
    end
  endtask

  // one clock cycle, call this while clk is low
  task automatic cycle(input logic rn, input logic we,
                       input logic [DATA_WIDTH-1:0] wd, input logic re);
    begin
      rst_n = rn; wr_en = we; wr_data = wd; rd_en = re;
      #1 check("comb");   // outputs shouldn't react to the new inputs
      @(posedge clk);
      model_step(rn, we, wd, re);
      if (!rn) checking = 1'b1;
      #1 check("post-edge");
      cycle_n++;
      @(negedge clk);
    end
  endtask

  task automatic do_reset();     cycle(1'b0, 1'b0, '0, 1'b0); endtask
  task automatic do_idle();      cycle(1'b1, 1'b0, '0, 1'b0); endtask
  task automatic do_write(input logic [DATA_WIDTH-1:0] d); cycle(1'b1, 1'b1, d, 1'b0); endtask
  task automatic do_read();      cycle(1'b1, 1'b0, '0, 1'b1); endtask
  task automatic do_rw(input logic [DATA_WIDTH-1:0] d);    cycle(1'b1, 1'b1, d, 1'b1); endtask

  task automatic start_test(input string name);
    begin
      test_name = name;
      n_tests++;
      $display("INFO  starting test %0d: %s", n_tests, name);
    end
  endtask

  function automatic logic [DATA_WIDTH-1:0] rand_data();
    logic [DATA_WIDTH-1:0] d;
    integer k;
    begin
      d = '0;
      for (k = 0; k < DATA_WIDTH; k += 32) d = (d << 32) | $random(seed);
      rand_data = d;
    end
  endfunction

  // tests
  integer i, r, phase_kind;
  logic [DATA_WIDTH-1:0] pat;

  initial begin
    if ($value$plusargs("SEED=%d", seed))          ;
    if ($value$plusargs("RAND_CYCLES=%d", rand_cycles)) ;
    if ($value$plusargs("MAX_ERR_PRINT=%d", max_err_print)) ;
    if ($test$plusargs("DUMP")) begin
      $dumpfile("wave.vcd");
      $dumpvars(0, tb_sync_fifo);
    end
    $display("INFO  tb_sync_fifo  DATA_WIDTH=%0d DEPTH=%0d SEED=%0d RAND_CYCLES=%0d",
             DATA_WIDTH, DEPTH, seed, rand_cycles);

    m_wp = 0; m_rp = 0; m_cnt = 0; m_rd = '0;
    rst_n = 1'b0; wr_en = 1'b0; rd_en = 1'b0; wr_data = '0;
    @(negedge clk);

    start_test("reset_values");
    do_reset(); do_reset(); do_idle();

    start_test("single_write_read");
    do_write(rand_data()); do_idle(); do_read(); do_idle(); do_idle();

    start_test("fill_to_full_patterns");   // 0s, 1s, 1010.., walking 1
    for (i = 0; i < DEPTH; i++) begin
      case (i % 4)
        0: pat = '0;
        1: pat = '1;
        2: pat = {(DATA_WIDTH+1)/2{2'b10}};
        default: pat = {{(DATA_WIDTH-1){1'b0}}, 1'b1} << (i % DATA_WIDTH);
      endcase
      do_write(pat);
    end

    start_test("overflow_attempt");
    for (i = 0; i < 3; i++) do_write(rand_data());
    do_idle();

    start_test("drain_to_empty");
    for (i = 0; i < DEPTH; i++) do_read();

    start_test("underflow_attempt");
    for (i = 0; i < 3; i++) do_read();
    do_idle();

    start_test("simultaneous_rw_when_empty");
    do_rw(rand_data()); do_rw(rand_data()); do_read(); do_read(); do_idle();

    start_test("simultaneous_rw_when_full");
    for (i = 0; i < DEPTH; i++) do_write(rand_data());
    do_rw(rand_data());   // full, only the read happens
    do_rw(rand_data());   // now both happen
    for (i = 0; i < DEPTH; i++) do_read();

    start_test("simultaneous_rw_mid");
    for (i = 0; i < DEPTH/2; i++) do_write(rand_data());
    for (i = 0; i < 2*DEPTH; i++) do_rw(rand_data());
    for (i = 0; i < DEPTH/2; i++) do_read();

    start_test("pointer_wraparound");
    for (i = 0; i < 3*DEPTH; i++) begin do_write(rand_data()); do_read(); end
    do_write(rand_data()); do_write(rand_data());
    for (i = 0; i < 3*DEPTH; i++) do_rw(rand_data());
    do_read(); do_read();

    start_test("reset_mid_operation");
    for (i = 0; i < DEPTH/2 + 1; i++) do_write(rand_data());
    do_read();
    cycle(1'b0, 1'b1, rand_data(), 1'b1);   // reset with wr_en and rd_en high
    do_read();                              // should be empty now
    do_write(rand_data()); do_read(); do_idle();

    start_test("idle_hold");
    do_write(rand_data()); do_write(rand_data()); do_read();
    for (i = 0; i < 5; i++) do_idle();
    do_read(); do_idle();

    start_test("constrained_random");
    // every 50 cycles pick: 0 write heavy, 1 read heavy, 2 balanced
    for (i = 0; i < rand_cycles; i++) begin
      if (i % 50 == 0) phase_kind = ($random(seed) & 32'h7fff_ffff) % 3;
      r = ($random(seed) & 32'h7fff_ffff) % 100;
      if (r == 0) do_reset();
      else case (phase_kind)
        0: cycle(1'b1, r < 80, rand_data(), r >= 70);
        1: cycle(1'b1, r < 25, rand_data(), r >= 20);
        default: cycle(1'b1, r < 55, rand_data(), r >= 45);
      endcase
    end

    finish_run();
  end

  // summary
  task automatic cov_line(input string name, input integer hits, inout integer missed);
    begin
      $display("COVER %-24s hits=%0d %s", name, hits, (hits > 0) ? "" : "<-- NOT HIT");
      if (hits == 0) missed++;
    end
  endtask

  task automatic finish_run();
    integer missed;
    begin
      missed = 0;
      cov_line("full",                 cov_full,        missed);
      cov_line("empty_after_data",     cov_empty_again, missed);
      cov_line("overflow_attempt",     cov_overflow,    missed);
      cov_line("underflow_attempt",    cov_underflow,   missed);
      cov_line("rw_when_empty",        cov_rw_empty,    missed);
      cov_line("rw_when_full",         cov_rw_full,     missed);
      cov_line("rw_mid",               cov_rw_mid,      missed);
      cov_line("write_ptr_wrap",       cov_wrap,        missed);
      cov_line("reset_with_data",      cov_reset_mid,   missed);
      if (n_errors == 0 && missed == 0)
        $display("TEST_RESULT: PASS tests=%0d cycles=%0d checks=%0d errors=0 coverage_missed=0",
                 n_tests, cycle_n, n_checks);
      else
        $display("TEST_RESULT: FAIL tests=%0d cycles=%0d checks=%0d errors=%0d coverage_missed=%0d",
                 n_tests, cycle_n, n_checks, n_errors, missed);
      $finish;
    end
  endtask

  // timeout so a broken DUT can't hang the run
  initial begin : watchdog
    integer wd_cycles;
    wd_cycles = 5000;
    if ($value$plusargs("RAND_CYCLES=%d", wd_cycles)) ;
    #(10 * (wd_cycles + 2000 + 40*DEPTH) + 1000);
    $display("ERROR test=%s cycle=%0d phase=watchdog signal=none expected=finish got=timeout", test_name, cycle_n);
    $display("TEST_RESULT: FAIL reason=timeout");
    $finish;
  end

endmodule
