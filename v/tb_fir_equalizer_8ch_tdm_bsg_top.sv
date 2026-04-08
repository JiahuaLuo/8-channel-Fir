`timescale 1ns/1ps

module tb_fir_equalizer_8ch_tdm_bsg_top;

  localparam int CH  = 8;
  localparam int TAP = 25;
  localparam int DW  = 8;
  localparam int WW  = 8;
  localparam int AW  = 24;

  logic                   clk;
  logic                   rst_n;

  // BSG-Link #1 logical data link
  // data_link_data = {channel_id[2:0], sample_data[7:0]}
  logic                   data_link_valid;
  logic [10:0]            data_link_data;
  logic                   data_link_ready;

  // BSG-Link #2 logical ctrl/debug link
  logic                   ctrl_link_valid;
  logic                   ctrl_link_write;
  logic [7:0]             ctrl_link_addr;
  logic [31:0]            ctrl_link_wdata;
  logic [31:0]            ctrl_link_rdata;
  logic                   ctrl_link_rvalid;
  logic                   ctrl_link_ready;

  // outputs
  logic [CH-1:0]          out_valid;
  logic [CH*DW-1:0]       out_data_u8_flat;
  logic [CH-1:0]          bit_valid;
  logic [CH-1:0]          out_bit;

  logic [7:0]             last_read_addr;

  // DUT
  fir_equalizer_8ch_tdm_bsg_top #(
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
  localparam logic [7:0] ADDR_MODE       = 8'h00;
  localparam logic [7:0] ADDR_SHIFT      = 8'h04;
  localparam logic [7:0] ADDR_THRESH     = 8'h08;
  localparam logic [7:0] ADDR_WADDR      = 8'h10;
  localparam logic [7:0] ADDR_WDATA      = 8'h14;
  localparam logic [7:0] ADDR_WCOMMIT    = 8'h18;
  localparam logic [7:0] ADDR_WREAD      = 8'h1C;
  localparam logic [7:0] ADDR_PROBE_SEL  = 8'h20;
  localparam logic [7:0] ADDR_PROBE_DATA = 8'h24;

  // ------------------------------------------------------------
  // Ctrl helpers
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

      repeat (2) @(posedge clk);
    end
  endtask

  task automatic program_weight(input int addr, input int value);
    begin
      ctrl_write_reg(ADDR_WADDR, addr);
      ctrl_write_reg(ADDR_WDATA, value);
      ctrl_write_reg(ADDR_WCOMMIT, 32'h1);
    end
  endtask

  // ------------------------------------------------------------
  // Data helpers
  // one transaction = {channel_id[2:0], sample_data[7:0]}
  // ------------------------------------------------------------
  task automatic send_sample(
    input int ch_id,
    input int sample_val
  );
    reg [10:0] payload;
    begin
      payload = {ch_id[2:0], sample_val[7:0]};

      @(posedge clk);
      data_link_valid <= 1'b1;
      data_link_data  <= payload;

      @(posedge clk);
      data_link_valid <= 1'b0;
      data_link_data  <= '0;
    end
  endtask

  task automatic select_probe(input int ch_sel, input int sig_sel);
    reg [31:0] sel_word;
    begin
      // [2:0]=channel, [5:3]=signal
      sel_word = 32'd0;
      sel_word[2:0] = ch_sel[2:0];
      sel_word[5:3] = sig_sel[2:0];
      ctrl_write_reg(ADDR_PROBE_SEL, sel_word);
    end
  endtask

  integer i;

  // ------------------------------------------------------------
  // Main stimulus
  // ------------------------------------------------------------
  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_fir_equalizer_8ch_tdm_bsg_top);

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

    // --------------------------------------------------------
    // 1. configure shared mode / shift / threshold
    // --------------------------------------------------------
    ctrl_write_reg(ADDR_MODE,   32'h0000_0000); // offset=0, bypass=0
    ctrl_write_reg(ADDR_SHIFT,  32'd5);
    ctrl_write_reg(ADDR_THRESH, 32'd128);

    ctrl_read_reg(ADDR_MODE);
    ctrl_read_reg(ADDR_SHIFT);
    ctrl_read_reg(ADDR_THRESH);

    // --------------------------------------------------------
    // 2. program symmetric positive weights
    // --------------------------------------------------------
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

    // verify weight readback
    ctrl_write_reg(ADDR_WADDR, 12);
    ctrl_read_reg(ADDR_WREAD);

    // --------------------------------------------------------
    // 3. Round-robin sample feeding
    // Each transaction updates only one selected channel
    // --------------------------------------------------------

    // round 1
    send_sample(0, 10);
    send_sample(1, 20);
    send_sample(2, 30);
    send_sample(3, 40);
    send_sample(4, 50);
    send_sample(5, 60);
    send_sample(6, 70);
    send_sample(7, 80);

    // round 2
    send_sample(0, 20);
    send_sample(1, 30);
    send_sample(2, 40);
    send_sample(3, 50);
    send_sample(4, 60);
    send_sample(5, 70);
    send_sample(6, 80);
    send_sample(7, 90);

    // round 3
    send_sample(0, 30);
    send_sample(1, 40);
    send_sample(2, 50);
    send_sample(3, 60);
    send_sample(4, 70);
    send_sample(5, 80);
    send_sample(6, 90);
    send_sample(7, 100);

    // round 4
    send_sample(0, 40);
    send_sample(1, 50);
    send_sample(2, 60);
    send_sample(3, 70);
    send_sample(4, 80);
    send_sample(5, 90);
    send_sample(6, 100);
    send_sample(7, 110);

    // round 5
    send_sample(0, 50);
    send_sample(1, 60);
    send_sample(2, 70);
    send_sample(3, 80);
    send_sample(4, 90);
    send_sample(5, 100);
    send_sample(6, 110);
    send_sample(7, 120);

    repeat (20) @(posedge clk);

    // --------------------------------------------------------
    // 4. Probe reads
    // probe_sig_sel:
    //   0 -> input sample snapshot
    //   1 -> raw FIR output snapshot
    //   2 -> final output snapshot
    //   3 -> out_bit
    //   4 -> out_valid
    //   5 -> bit_valid
    // --------------------------------------------------------
    select_probe(0, 0); ctrl_read_reg(ADDR_PROBE_DATA); // CH0 input
    select_probe(0, 1); ctrl_read_reg(ADDR_PROBE_DATA); // CH0 raw fir
    select_probe(7, 1); ctrl_read_reg(ADDR_PROBE_DATA); // CH7 raw fir
    select_probe(7, 2); ctrl_read_reg(ADDR_PROBE_DATA); // CH7 final out
    select_probe(7, 3); ctrl_read_reg(ADDR_PROBE_DATA); // CH7 bit
    select_probe(7, 4); ctrl_read_reg(ADDR_PROBE_DATA); // CH7 out_valid seen
    select_probe(7, 5); ctrl_read_reg(ADDR_PROBE_DATA); // CH7 bit_valid seen

    // --------------------------------------------------------
    // 5. Bypass mode
    // --------------------------------------------------------
    ctrl_write_reg(ADDR_MODE, 32'h0000_0002); // bypass = 1

    send_sample(0, 100);
    send_sample(1, 110);
    send_sample(2, 120);
    send_sample(3, 130);
    send_sample(4, 140);
    send_sample(5, 150);
    send_sample(6, 160);
    send_sample(7, 170);

    send_sample(0, 101);
    send_sample(1, 111);
    send_sample(2, 121);
    send_sample(3, 131);
    send_sample(4, 141);
    send_sample(5, 151);
    send_sample(6, 161);
    send_sample(7, 171);

    repeat (10) @(posedge clk);

    // probe after bypass
    select_probe(0, 1); ctrl_read_reg(ADDR_PROBE_DATA); // CH0 raw fir snapshot
    select_probe(0, 2); ctrl_read_reg(ADDR_PROBE_DATA); // CH0 final output snapshot
    select_probe(7, 1); ctrl_read_reg(ADDR_PROBE_DATA); // CH7 raw fir snapshot
    select_probe(7, 2); ctrl_read_reg(ADDR_PROBE_DATA); // CH7 final output snapshot

    repeat (20) @(posedge clk);
    $finish;
  end

  // ------------------------------------------------------------
  // Console output
  // ------------------------------------------------------------
  always @(posedge clk) begin
    for (int c = 0; c < CH; c++) begin
      if (out_valid[c]) begin
        $display("[%0t] CH%0d out_valid=1 out_data=%0d", $time, c, out_data_u8_flat[c*DW +: DW]);
      end
      if (bit_valid[c]) begin
        $display("[%0t] CH%0d bit_valid=1 out_bit=%0d", $time, c, out_bit[c]);
      end
    end

    if (ctrl_link_rvalid) begin
      $display("[%0t] CTRL READ addr=0x%0h rdata=0x%08h", $time, last_read_addr, ctrl_link_rdata);
    end
  end

endmodule
