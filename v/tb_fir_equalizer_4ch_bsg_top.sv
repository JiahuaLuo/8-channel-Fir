`timescale 1ns/1ps

module tb_fir_equalizer_4ch_bsg_top;

  localparam int CH  = 4;
  localparam int TAP = 25;
  localparam int DW  = 8;
  localparam int WW  = 8;
  localparam int AW  = 24;

  logic                   clk;
  logic                   rst_n;

  // -------------------------------
  // "BSG-Link #1" logical data link
  // -------------------------------
  logic                   data_link_valid;
  logic [CH*DW-1:0]       data_link_data;
  logic                   data_link_ready;

  // -------------------------------
  // "BSG-Link #2" logical ctrl/debug link
  // -------------------------------
  logic                   ctrl_link_valid;
  logic                   ctrl_link_write;
  logic [7:0]             ctrl_link_addr;
  logic [31:0]            ctrl_link_wdata;
  logic [31:0]            ctrl_link_rdata;
  logic                   ctrl_link_rvalid;
  logic                   ctrl_link_ready;
  logic [7:0]             last_read_addr;

  // outputs
  logic [CH-1:0]          out_valid;
  logic [CH*DW-1:0]       out_data_u8_flat;
  logic [CH-1:0]          bit_valid;
  logic [CH-1:0]          out_bit;

  // DUT
  fir_equalizer_4ch_bsg_top #(
    .CH (CH),
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .AW (AW)
  ) dut (
    .clk             (clk),
    .rst_n           (rst_n),

    .data_link_valid (data_link_valid),
    .data_link_data  (data_link_data),
    .data_link_ready (data_link_ready),

    .ctrl_link_valid (ctrl_link_valid),
    .ctrl_link_write (ctrl_link_write),
    .ctrl_link_addr  (ctrl_link_addr),
    .ctrl_link_wdata (ctrl_link_wdata),
    .ctrl_link_rdata (ctrl_link_rdata),
    .ctrl_link_rvalid(ctrl_link_rvalid),
    .ctrl_link_ready (ctrl_link_ready),

    .out_valid       (out_valid),
    .out_data_u8_flat(out_data_u8_flat),
    .bit_valid       (bit_valid),
    .out_bit         (out_bit)
  );

  // ------------------------------------------------------------
  // Clock
  // ------------------------------------------------------------
  initial clk = 1'b0;
  always #10 clk = ~clk; // 50 MHz -> 20 ns period

  // ------------------------------------------------------------
  // Address map (must match cfg_debug_ctrl.sv)
  // ------------------------------------------------------------
  localparam logic [7:0] ADDR_MODE       = 8'h00; // [0]=offset_en, [1]=bypass_en
  localparam logic [7:0] ADDR_SHIFT      = 8'h04; // [4:0]
  localparam logic [7:0] ADDR_THRESH     = 8'h08; // [7:0]
  localparam logic [7:0] ADDR_WADDR      = 8'h10;
  localparam logic [7:0] ADDR_WDATA      = 8'h14;
  localparam logic [7:0] ADDR_WCOMMIT    = 8'h18;
  localparam logic [7:0] ADDR_WREAD      = 8'h1C;
  localparam logic [7:0] ADDR_PROBE_SEL  = 8'h20; // [1:0]=ch, [5:3]=sig
  localparam logic [7:0] ADDR_PROBE_DATA = 8'h24;

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  task automatic ctrl_write_reg(input [7:0] addr, input [31:0] data);
    begin
      @(posedge clk);
      ctrl_link_valid <= 1'b1;
      ctrl_link_write <= 1'b1;
      ctrl_link_addr  <= addr;
      ctrl_link_wdata <= data;

      @(posedge clk);
      ctrl_link_valid <= 1'b0;
      ctrl_link_write <= 1'b0;
      ctrl_link_addr  <= '0;
      ctrl_link_wdata <= '0;
    end
  endtask

  task automatic ctrl_read_reg(input [7:0] addr);
    begin
      @(posedge clk);
      ctrl_link_valid <= 1'b1;
      ctrl_link_write <= 1'b0;
      ctrl_link_addr  <= addr;
      ctrl_link_wdata <= 32'd0;
      last_read_addr  <= addr;

      @(posedge clk);
      ctrl_link_valid <= 1'b0;
      ctrl_link_addr  <= '0;

      // give one or two cycles for readback visibility
      repeat (2) @(posedge clk);
    end
  endtask

  task automatic program_weight(input int addr, input int value);
    begin
      ctrl_write_reg(ADDR_WADDR,  addr);
      ctrl_write_reg(ADDR_WDATA,  value);
      ctrl_write_reg(ADDR_WCOMMIT, 32'h1);
    end
  endtask

  task automatic send_4ch_sample(
    input int ch0,
    input int ch1,
    input int ch2,
    input int ch3
  );
    begin
      @(posedge clk);
      data_link_valid <= 1'b1;
      data_link_data  <= {ch3[7:0], ch2[7:0], ch1[7:0], ch0[7:0]};

      @(posedge clk);
      data_link_valid <= 1'b0;
      data_link_data  <= '0;
    end
  endtask

  task automatic select_probe(input int ch_sel, input int sig_sel);
    reg [31:0] sel_word;
    begin
      // [1:0]=channel, [5:3]=signal
      sel_word = 32'd0;
      sel_word[1:0] = ch_sel[1:0];
      sel_word[5:3] = sig_sel[2:0];
      ctrl_write_reg(ADDR_PROBE_SEL, sel_word);
    end
  endtask

  integer i;

  // ------------------------------------------------------------
  // Test sequence
  // ------------------------------------------------------------
  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_fir_equalizer_4ch_bsg_top);

    rst_n           = 1'b0;

    data_link_valid = 1'b0;
    data_link_data  = '0;

    ctrl_link_valid = 1'b0;
    ctrl_link_write = 1'b0;
    ctrl_link_addr  = '0;
    ctrl_link_wdata = '0;
    last_read_addr  = '0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // -----------------------------------------
    // Step 1: configure shared mode/shift/thresh
    // mode[0]=offset_en, mode[1]=bypass_en
    // -----------------------------------------
    ctrl_write_reg(ADDR_MODE,   32'h0000_0000); // offset=0, bypass=0
    ctrl_write_reg(ADDR_SHIFT,  32'd5);
    ctrl_write_reg(ADDR_THRESH, 32'd128);

    // optional readback check
    ctrl_read_reg(ADDR_MODE);
    ctrl_read_reg(ADDR_SHIFT);
    ctrl_read_reg(ADDR_THRESH);

    // -----------------------------------------
    // Step 2: program 25-tap symmetric positive weights
    // -----------------------------------------
    program_weight(0,  1);
    program_weight(1,  1);
    program_weight(2,  1);
    program_weight(3,  2);
    program_weight(4,  2);
    program_weight(5,  3);
    program_weight(6,  3);
    program_weight(7,  4);
    program_weight(8,  4);
    program_weight(9,  5);
    program_weight(10, 6);
    program_weight(11, 7);
    program_weight(12, 8);
    program_weight(13, 7);
    program_weight(14, 6);
    program_weight(15, 5);
    program_weight(16, 4);
    program_weight(17, 4);
    program_weight(18, 3);
    program_weight(19, 3);
    program_weight(20, 2);
    program_weight(21, 2);
    program_weight(22, 1);
    program_weight(23, 1);
    program_weight(24, 1);

    ctrl_write_reg(ADDR_WADDR, 32'd12);
    ctrl_read_reg(ADDR_WREAD);

    // -----------------------------------------
    // Step 3: send data over "BSG-link #1"
    // 4 channels, different streams
    // -----------------------------------------
    send_4ch_sample(10, 20, 30, 40);
    send_4ch_sample(20, 30, 40, 50);
    send_4ch_sample(30, 40, 50, 60);
    send_4ch_sample(40, 50, 60, 70);
    send_4ch_sample(50, 60, 70, 80);

    repeat (40) @(posedge clk);

    // -----------------------------------------
    // Step 4: read probes back over "BSG-link #2"
    // probe_sig_sel:
    //   0 -> last input sample
    //   1 -> last raw FIR output
    //   2 -> last final lane output
    //   3 -> last out_bit
    //   4 -> seen_out_valid
    //   5 -> seen_bit_valid
    //   6 -> mode summary
    // -----------------------------------------

    // Read CH0 input sample probe
    select_probe(0, 0);
    ctrl_read_reg(ADDR_PROBE_DATA);

    // Read CH0 FIR output probe
    select_probe(0, 1);
    ctrl_read_reg(ADDR_PROBE_DATA);

    // Read CH0 final lane output probe
    select_probe(0, 2);
    ctrl_read_reg(ADDR_PROBE_DATA);

    // Read CH3 FIR output probe
    select_probe(3, 1);
    ctrl_read_reg(ADDR_PROBE_DATA);

    // Read CH3 bit output probe
    select_probe(3, 3);
    ctrl_read_reg(ADDR_PROBE_DATA);

    select_probe(3, 4);
    ctrl_read_reg(ADDR_PROBE_DATA);

    select_probe(3, 5);
    ctrl_read_reg(ADDR_PROBE_DATA);

    select_probe(0, 6);
    ctrl_read_reg(ADDR_PROBE_DATA);

    // -----------------------------------------
    // Step 5: turn on bypass through ctrl link
    // mode[1] = bypass_en
    // -----------------------------------------
    ctrl_write_reg(ADDR_MODE, 32'h0000_0002); // offset=0, bypass=1

    send_4ch_sample(100, 110, 120, 130);
    send_4ch_sample(101, 111, 121, 131);

    repeat (20) @(posedge clk);

    // Compare raw FIR output vs final lane output in bypass mode
    select_probe(0, 1);
    ctrl_read_reg(ADDR_PROBE_DATA);

    select_probe(0, 2);
    ctrl_read_reg(ADDR_PROBE_DATA);

    select_probe(3, 1);
    ctrl_read_reg(ADDR_PROBE_DATA);

    select_probe(3, 2);
    ctrl_read_reg(ADDR_PROBE_DATA);

    select_probe(0, 6);
    ctrl_read_reg(ADDR_PROBE_DATA);

    repeat (20) @(posedge clk);
    $finish;
  end

  // ------------------------------------------------------------
  // Console prints
  // ------------------------------------------------------------
  always @(posedge clk) begin
    if (out_valid[0]) $display("[%0t] CH0 out_valid=1 out_data=%0d", $time, out_data_u8_flat[7:0]);
    if (out_valid[1]) $display("[%0t] CH1 out_valid=1 out_data=%0d", $time, out_data_u8_flat[15:8]);
    if (out_valid[2]) $display("[%0t] CH2 out_valid=1 out_data=%0d", $time, out_data_u8_flat[23:16]);
    if (out_valid[3]) $display("[%0t] CH3 out_valid=1 out_data=%0d", $time, out_data_u8_flat[31:24]);

    if (bit_valid[0]) $display("[%0t] CH0 bit_valid=1 out_bit=%0d", $time, out_bit[0]);
    if (bit_valid[1]) $display("[%0t] CH1 bit_valid=1 out_bit=%0d", $time, out_bit[1]);
    if (bit_valid[2]) $display("[%0t] CH2 bit_valid=1 out_bit=%0d", $time, out_bit[2]);
    if (bit_valid[3]) $display("[%0t] CH3 bit_valid=1 out_bit=%0d", $time, out_bit[3]);

    if (ctrl_link_rvalid) begin
      $display("[%0t] CTRL READ addr=0x%0h rdata=0x%08h", $time, last_read_addr, ctrl_link_rdata);
    end
  end

endmodule
