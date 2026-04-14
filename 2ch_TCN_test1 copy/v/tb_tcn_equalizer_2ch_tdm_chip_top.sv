`timescale 1ns/1ps

module tb_tcn_equalizer_2ch_tdm_chip_top;

  localparam int CH  = 2;
  localparam int TAP = 25;
  localparam int DW  = 8;
  localparam int WW  = 8;
  localparam int AW  = 24;

  logic                   clk;
  logic                   rst_n;
  logic                   sample_valid;
  logic [$clog2(CH)-1:0]  sample_channel_id;
  logic [DW-1:0]          sample_data;
  logic                   sample_ready;
  logic                   cfg_valid;
  logic                   cfg_write;
  logic                   cfg_ready;
  logic [3:0]             cfg_data;
  logic                   cfg_resp_valid;
  logic [3:0]             cfg_resp_data;
  logic [CH-1:0]          out_bit;
  logic                   out_frame_valid;
  logic [$clog2(CH)-1:0]  out_channel_id;
  logic [31:0]            last_cfg_readback;
  logic [31:0]            rdata;

  tcn_equalizer_2ch_tdm_chip_top #(
    .CH(CH),
    .TAP(TAP),
    .DW(DW),
    .WW(WW),
    .AW(AW)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .sample_valid(sample_valid),
    .sample_channel_id(sample_channel_id),
    .sample_data(sample_data),
    .sample_ready(sample_ready),
    .cfg_valid(cfg_valid),
    .cfg_write(cfg_write),
    .cfg_ready(cfg_ready),
    .cfg_data(cfg_data),
    .cfg_resp_valid(cfg_resp_valid),
    .cfg_resp_data(cfg_resp_data),
    .out_bit(out_bit),
    .out_frame_valid(out_frame_valid),
    .out_channel_id(out_channel_id)
  );

  localparam time CLK_HALF_PERIOD = 10ns;

  initial clk = 1'b0;
  always #(CLK_HALF_PERIOD) clk = ~clk;

  localparam logic [7:0] ADDR_MODE       = 8'h00;
  localparam logic [7:0] ADDR_SHIFT      = 8'h04;
  localparam logic [7:0] ADDR_THRESH     = 8'h08;
  localparam logic [7:0] ADDR_WADDR      = 8'h10;
  localparam logic [7:0] ADDR_WDATA      = 8'h14;
  localparam logic [7:0] ADDR_WCOMMIT    = 8'h18;
  localparam logic [7:0] ADDR_WREAD      = 8'h1C;
  localparam logic [7:0] ADDR_PROBE_SEL  = 8'h20;
  localparam logic [7:0] ADDR_PROBE_DATA = 8'h24;
  localparam int RESET_CYCLES            = 20;
  localparam int POST_RESET_CYCLES       = 20;
  localparam int NIBBLE_GAP_CYCLES       = 2;
  localparam int CFG_GAP_CYCLES          = 4;
  localparam int SAMPLE_GAP_CYCLES       = 1;
  localparam int WAIT_CFG_READY_MAX_CYCLES = 500;
  localparam int WAIT_CFG_RESP_MAX_CYCLES  = 500;
  localparam int SIM_TIMEOUT_CYCLES        = 20000;
  localparam int CAPTURE_MAX_EVENTS        = 32;
  localparam int CAPTURE_NONE              = 0;
  localparam int CAPTURE_ISO_A             = 1;
  localparam int CAPTURE_ISO_B             = 2;

  int capture_mode;
  int iso_a_count;
  int iso_b_count;
  logic signed [DW-1:0] iso_a_scores [CAPTURE_MAX_EVENTS];
  logic signed [DW-1:0] iso_b_scores [CAPTURE_MAX_EVENTS];
  logic                 iso_a_bits   [CAPTURE_MAX_EVENTS];
  logic                 iso_b_bits   [CAPTURE_MAX_EVENTS];

  task automatic clear_iso_capture();
    integer idx;
    begin
      capture_mode = CAPTURE_NONE;
      iso_a_count = 0;
      iso_b_count = 0;
      for (idx = 0; idx < CAPTURE_MAX_EVENTS; idx = idx + 1) begin
        iso_a_scores[idx] = '0;
        iso_b_scores[idx] = '0;
        iso_a_bits[idx] = 1'b0;
        iso_b_bits[idx] = 1'b0;
      end
    end
  endtask

  task automatic reset_dut();
    begin
      @(negedge clk);
      rst_n             <= 1'b0;
      sample_valid      <= 1'b0;
      sample_channel_id <= '0;
      sample_data       <= '0;
      cfg_valid         <= 1'b0;
      cfg_write         <= 1'b0;
      cfg_data          <= '0;
      last_cfg_readback <= '0;

      repeat (RESET_CYCLES) @(posedge clk);
      @(negedge clk);
      rst_n <= 1'b1;
      repeat (POST_RESET_CYCLES) @(posedge clk);
    end
  endtask

  task automatic configure_datapath(input logic [31:0] mode_word, input logic [7:0] thresh_byte);
    begin
      cfg_write_reg(ADDR_MODE, mode_word);
      cfg_write_reg(ADDR_SHIFT, 32'd0);
      cfg_write_reg(ADDR_THRESH, {24'd0, thresh_byte});
    end
  endtask

  task automatic wait_for_channel_output(
    input int channel_id,
    output logic [CH-1:0] bits,
    output logic signed [DW-1:0] score
  );
    int wait_cycles;
    begin
      wait_cycles = 0;
      while (!(out_frame_valid && (out_channel_id == channel_id[$clog2(CH)-1:0]))) begin
        if (wait_cycles >= SIM_TIMEOUT_CYCLES) begin
          $fatal(1, "[%0t] Timeout waiting for output on channel %0d", $time, channel_id);
        end
        @(posedge clk);
        wait_cycles++;
      end

      bits = out_bit;
      score = dut.u_core.out_data_u8_flat[channel_id*DW +: DW];
    end
  endtask

  task automatic run_smoke_test();
    begin
      $display("[%0t] ==== Smoke test ====", $time);
      configure_datapath(32'h0000_0000, 8'd0);

      cfg_read_reg(ADDR_MODE, rdata);
      cfg_read_reg(ADDR_SHIFT, rdata);
      cfg_read_reg(ADDR_THRESH, rdata);
      cfg_read_reg(ADDR_WREAD, rdata);

      send_sample(0, 8'd1);
      send_sample(1, 8'd100);
      send_sample(0, 8'd2);
      send_sample(1, 8'd101);
      send_sample(0, 8'd3);
      send_sample(1, 8'd102);
      send_sample(0, 8'd4);
      send_sample(1, 8'd103);
      send_sample(0, 8'd5);
      send_sample(1, 8'd104);

      repeat (10) @(posedge clk);

      select_probe(0, 0);
      cfg_read_reg(ADDR_PROBE_DATA, rdata);
      $display("[%0t] PROBE CH0 INPUT  = 0x%08h", $time, rdata);
      select_probe(1, 0);
      cfg_read_reg(ADDR_PROBE_DATA, rdata);
      $display("[%0t] PROBE CH1 INPUT  = 0x%08h", $time, rdata);
      select_probe(0, 1);
      cfg_read_reg(ADDR_PROBE_DATA, rdata);
      $display("[%0t] PROBE CH0 SCORE  = 0x%08h", $time, rdata);
      select_probe(1, 1);
      cfg_read_reg(ADDR_PROBE_DATA, rdata);
      $display("[%0t] PROBE CH1 SCORE  = 0x%08h", $time, rdata);

      cfg_write_reg(ADDR_MODE, 32'h0000_0002);

      send_sample(0, 8'd10);
      send_sample(1, 8'd110);
      send_sample(0, 8'd11);
      send_sample(1, 8'd111);

      repeat (12) @(posedge clk);
    end
  endtask

  task automatic run_isolation_pattern(input int ch1_value);
    int idx;
    begin
      for (idx = 0; idx < 6; idx = idx + 1) begin
        send_sample(0, idx + 1);
        send_sample(1, ch1_value);
      end
    end
  endtask

  task automatic compare_isolation_results();
    int idx;
    begin
      if (iso_a_count != iso_b_count) begin
        $fatal(1, "[%0t] Isolation mismatch: ch0 event count A=%0d B=%0d",
          $time, iso_a_count, iso_b_count);
      end

      if (iso_a_count == 0) begin
        $fatal(1, "[%0t] Isolation test captured no ch0 outputs", $time);
      end

      for (idx = 0; idx < iso_a_count; idx = idx + 1) begin
        $display("[%0t] ISO compare idx=%0d A(score=%0d bit=%0b) B(score=%0d bit=%0b)",
          $time, idx, iso_a_scores[idx], iso_a_bits[idx], iso_b_scores[idx], iso_b_bits[idx]);
        if ((iso_a_scores[idx] !== iso_b_scores[idx]) || (iso_a_bits[idx] !== iso_b_bits[idx])) begin
          $fatal(1, "[%0t] Isolation mismatch at idx=%0d", $time, idx);
        end
      end

      $display("[%0t] Isolation PASS: ch1 stimulus changes did not affect ch0 outputs", $time);
    end
  endtask

  task automatic run_isolation_test();
    begin
      $display("[%0t] ==== Isolation test A: ch1 all zero ====", $time);
      clear_iso_capture();
      reset_dut();
      configure_datapath(32'h0000_0000, 8'd0);
      capture_mode = CAPTURE_ISO_A;
      run_isolation_pattern(0);
      repeat (12) @(posedge clk);
      capture_mode = CAPTURE_NONE;

      $display("[%0t] ==== Isolation test B: ch1 all 100 ====", $time);
      reset_dut();
      configure_datapath(32'h0000_0000, 8'd0);
      capture_mode = CAPTURE_ISO_B;
      run_isolation_pattern(100);
      repeat (12) @(posedge clk);
      capture_mode = CAPTURE_NONE;

      compare_isolation_results();
    end
  endtask

  task automatic run_signed_threshold_test();
    logic [CH-1:0] observed_bits;
    logic signed [DW-1:0] observed_score;
    begin
      $display("[%0t] ==== Signed threshold semantics test ====", $time);

      reset_dut();
      configure_datapath(32'h0000_0002, 8'h80);
      send_sample(0, 8'd0);
      wait_for_channel_output(0, observed_bits, observed_score);
      $display("[%0t] THRESH=0x80 score=%0d bits=%b", $time, observed_score, observed_bits);
      if (observed_bits[0] !== 1'b1) begin
        $fatal(1, "[%0t] Expected threshold 0x80 to act as signed -128", $time);
      end

      reset_dut();
      configure_datapath(32'h0000_0002, 8'h7F);
      send_sample(0, 8'd0);
      wait_for_channel_output(0, observed_bits, observed_score);
      $display("[%0t] THRESH=0x7F score=%0d bits=%b", $time, observed_score, observed_bits);
      if (observed_bits[0] !== 1'b0) begin
        $fatal(1, "[%0t] Expected threshold 0x7F to act as signed +127", $time);
      end
    end
  endtask

  task automatic wait_cfg_ready();
    int wait_cycles;
    begin
      wait_cycles = 0;
      while (cfg_ready !== 1'b1) begin
        if (wait_cycles >= WAIT_CFG_READY_MAX_CYCLES) begin
          $fatal(1, "[%0t] Timeout waiting for cfg_ready", $time);
        end
        @(posedge clk);
        wait_cycles++;
      end
    end
  endtask

  task automatic recv_cfg_nibble(output logic [3:0] nib);
    int wait_cycles;
    begin
      wait_cycles = 0;
      @(posedge clk);
      while (cfg_resp_valid !== 1'b1) begin
        if (wait_cycles >= WAIT_CFG_RESP_MAX_CYCLES) begin
          $fatal(1, "[%0t] Timeout waiting for cfg_resp_valid (0x%08h)",
            $time, last_cfg_readback);
        end
        @(posedge clk);
        wait_cycles++;
      end
      nib = cfg_resp_data;
    end
  endtask

  task automatic send_cfg_nibble(input logic wr, input logic [3:0] nib);
    begin
      wait_cfg_ready();
      @(negedge clk);
      cfg_valid <= 1'b1;
      cfg_write <= wr;
      cfg_data  <= nib;

      @(negedge clk);
      cfg_valid <= 1'b0;
      cfg_data  <= '0;

      repeat (NIBBLE_GAP_CYCLES) @(posedge clk);
    end
  endtask

  task automatic cfg_write_reg(input logic [7:0] addr, input logic [31:0] data);
    begin
      send_cfg_nibble(1'b1, addr[7:4]);
      send_cfg_nibble(1'b1, addr[3:0]);
      send_cfg_nibble(1'b1, data[31:28]);
      send_cfg_nibble(1'b1, data[27:24]);
      send_cfg_nibble(1'b1, data[23:20]);
      send_cfg_nibble(1'b1, data[19:16]);
      send_cfg_nibble(1'b1, data[15:12]);
      send_cfg_nibble(1'b1, data[11:8]);
      send_cfg_nibble(1'b1, data[7:4]);
      send_cfg_nibble(1'b1, data[3:0]);
      repeat (CFG_GAP_CYCLES) @(posedge clk);
    end
  endtask

  task automatic cfg_read_reg(input logic [7:0] addr, output logic [31:0] rdata);
    integer k;
    logic [31:0] tmp;
    begin
      tmp = '0;
      send_cfg_nibble(1'b0, addr[7:4]);
      send_cfg_nibble(1'b0, addr[3:0]);

      for (k = 0; k < 8; k = k + 1) begin
        logic [3:0] nib;
        recv_cfg_nibble(nib);
        tmp = {tmp[27:0], nib};
      end

      rdata = tmp;
      last_cfg_readback = tmp;
      repeat (CFG_GAP_CYCLES) @(posedge clk);
    end
  endtask

  task automatic select_probe(input int ch_sel, input int sig_sel);
    logic [31:0] sel_word;
    begin
      sel_word = '0;
      sel_word[$clog2(CH)-1:0] = ch_sel[$clog2(CH)-1:0];
      sel_word[5:3] = sig_sel[2:0];
      cfg_write_reg(ADDR_PROBE_SEL, sel_word);
    end
  endtask

  task automatic send_sample(input int ch_id, input int sample_val);
    begin
      @(negedge clk);
      sample_valid      <= 1'b1;
      sample_channel_id <= ch_id[$clog2(CH)-1:0];
      sample_data       <= sample_val[DW-1:0];

      @(negedge clk);
      sample_valid      <= 1'b0;
      sample_channel_id <= '0;
      sample_data       <= '0;

      repeat (SAMPLE_GAP_CYCLES) @(posedge clk);
    end
  endtask

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_tcn_equalizer_2ch_tdm_chip_top);

    rst_n             = 1'b0;
    sample_valid      = 1'b0;
    sample_channel_id = '0;
    sample_data       = '0;
    cfg_valid         = 1'b0;
    cfg_write         = 1'b0;
    cfg_data          = '0;
    last_cfg_readback = '0;
    clear_iso_capture();

    reset_dut();
    run_smoke_test();
    run_isolation_test();
    run_signed_threshold_test();

    $display("[%0t] All tb checks passed", $time);
    $finish;
  end

  always @(posedge clk) begin
    if (out_frame_valid) begin
      $display("[%0t] OUT valid ch=%0d bits=%b", $time, out_channel_id, out_bit);
    end
  end

  always @(posedge clk) begin
    if (rst_n && dut.u_core.out_valid[0]) begin
      unique case (capture_mode)
        CAPTURE_ISO_A: begin
          if (iso_a_count >= CAPTURE_MAX_EVENTS) begin
            $fatal(1, "[%0t] Isolation capture A overflow", $time);
          end
          iso_a_scores[iso_a_count] <= dut.u_core.out_data_u8_flat[0 +: DW];
          iso_a_bits[iso_a_count] <= dut.u_core.out_bit[0];
          iso_a_count <= iso_a_count + 1;
        end
        CAPTURE_ISO_B: begin
          if (iso_b_count >= CAPTURE_MAX_EVENTS) begin
            $fatal(1, "[%0t] Isolation capture B overflow", $time);
          end
          iso_b_scores[iso_b_count] <= dut.u_core.out_data_u8_flat[0 +: DW];
          iso_b_bits[iso_b_count] <= dut.u_core.out_bit[0];
          iso_b_count <= iso_b_count + 1;
        end
        default: begin
        end
      endcase
    end
  end

  initial begin
    repeat (SIM_TIMEOUT_CYCLES) @(posedge clk);
    $fatal(1, "[%0t] Testbench timeout after %0d cycles", $time, SIM_TIMEOUT_CYCLES);
  end

endmodule
