`timescale 1ns/1ps

module tb_fir_equalizer_8ch_tdm_chip_top;

  localparam int CH  = 8;
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

  fir_equalizer_8ch_tdm_chip_top #(
    .CH (CH),
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .AW (AW)
  ) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .sample_valid     (sample_valid),
    .sample_channel_id(sample_channel_id),
    .sample_data      (sample_data),
    .sample_ready     (sample_ready),
    .cfg_valid        (cfg_valid),
    .cfg_write        (cfg_write),
    .cfg_ready        (cfg_ready),
    .cfg_data         (cfg_data),
    .cfg_resp_valid   (cfg_resp_valid),
    .cfg_resp_data    (cfg_resp_data),
    .out_bit          (out_bit),
    .out_frame_valid  (out_frame_valid),
    .out_channel_id   (out_channel_id)
  );

  initial clk = 1'b0;
  always #10 clk = ~clk;

  localparam logic [7:0] ADDR_MODE       = 8'h00;
  localparam logic [7:0] ADDR_SHIFT      = 8'h04;
  localparam logic [7:0] ADDR_THRESH     = 8'h08;
  localparam logic [7:0] ADDR_WADDR      = 8'h10;
  localparam logic [7:0] ADDR_WDATA      = 8'h14;
  localparam logic [7:0] ADDR_WCOMMIT    = 8'h18;
  localparam logic [7:0] ADDR_WREAD      = 8'h1C;
  localparam logic [7:0] ADDR_PROBE_SEL  = 8'h20;
  localparam logic [7:0] ADDR_PROBE_DATA = 8'h24;

  task automatic send_cfg_nibble(input logic wr, input logic [3:0] nib);
    begin
      @(posedge clk);
      cfg_valid <= 1'b1;
      cfg_write <= wr;
      cfg_data  <= nib;

      @(posedge clk);
      cfg_valid <= 1'b0;
      cfg_data  <= '0;
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
      repeat (2) @(posedge clk);
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
        @(posedge clk);
        while (!cfg_resp_valid) @(posedge clk);
        tmp = {tmp[27:0], cfg_resp_data};
      end

      rdata = tmp;
      last_cfg_readback = tmp;
    end
  endtask

  task automatic program_weight(input int addr, input int value);
    begin
      cfg_write_reg(ADDR_WADDR, addr);
      cfg_write_reg(ADDR_WDATA, value);
      cfg_write_reg(ADDR_WCOMMIT, 32'h1);
    end
  endtask

  task automatic select_probe(input int ch_sel, input int sig_sel);
    logic [31:0] sel_word;
    begin
      sel_word = '0;
      sel_word[2:0] = ch_sel[2:0];
      sel_word[5:3] = sig_sel[2:0];
      cfg_write_reg(ADDR_PROBE_SEL, sel_word);
    end
  endtask

  task automatic send_sample(input int ch_id, input int sample_val);
    begin
      @(posedge clk);
      sample_valid      <= 1'b1;
      sample_channel_id <= ch_id[$clog2(CH)-1:0];
      sample_data       <= sample_val[DW-1:0];

      @(posedge clk);
      sample_valid      <= 1'b0;
      sample_channel_id <= '0;
      sample_data       <= '0;
    end
  endtask

  integer i;
  logic [31:0] rdata;

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_fir_equalizer_8ch_tdm_chip_top);

    rst_n             = 1'b0;
    sample_valid      = 1'b0;
    sample_channel_id = '0;
    sample_data       = '0;
    cfg_valid         = 1'b0;
    cfg_write         = 1'b0;
    cfg_data          = '0;
    last_cfg_readback = '0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    cfg_write_reg(ADDR_MODE,   32'h0000_0000);
    cfg_write_reg(ADDR_SHIFT,  32'd5);
    cfg_write_reg(ADDR_THRESH, 32'd128);

    cfg_read_reg(ADDR_MODE, rdata);
    $display("[%0t] CFG READ addr=0x%0h rdata=0x%08h", $time, ADDR_MODE, rdata);
    cfg_read_reg(ADDR_SHIFT, rdata);
    $display("[%0t] CFG READ addr=0x%0h rdata=0x%08h", $time, ADDR_SHIFT, rdata);
    cfg_read_reg(ADDR_THRESH, rdata);
    $display("[%0t] CFG READ addr=0x%0h rdata=0x%08h", $time, ADDR_THRESH, rdata);

    program_weight(0, 1);
    program_weight(1, 1);
    program_weight(2, 1);
    program_weight(3, 2);
    program_weight(4, 2);
    program_weight(5, 3);
    program_weight(6, 3);
    program_weight(7, 4);
    program_weight(8, 4);
    program_weight(9, 5);
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

    cfg_write_reg(ADDR_WADDR, 32'd12);
    cfg_read_reg(ADDR_WREAD, rdata);
    $display("[%0t] CFG READ addr=0x%0h rdata=0x%08h", $time, ADDR_WREAD, rdata);

    send_sample(0, 10);
    send_sample(1, 20);
    send_sample(2, 30);
    send_sample(3, 40);
    send_sample(4, 50);
    send_sample(5, 60);
    send_sample(6, 70);
    send_sample(7, 80);

    send_sample(0, 20);
    send_sample(1, 30);
    send_sample(2, 40);
    send_sample(3, 50);
    send_sample(4, 60);
    send_sample(5, 70);
    send_sample(6, 80);
    send_sample(7, 90);

    send_sample(0, 30);
    send_sample(1, 40);
    send_sample(2, 50);
    send_sample(3, 60);
    send_sample(4, 70);
    send_sample(5, 80);
    send_sample(6, 90);
    send_sample(7, 100);

    send_sample(0, 40);
    send_sample(1, 50);
    send_sample(2, 60);
    send_sample(3, 70);
    send_sample(4, 80);
    send_sample(5, 90);
    send_sample(6, 100);
    send_sample(7, 110);

    send_sample(0, 50);
    send_sample(1, 60);
    send_sample(2, 70);
    send_sample(3, 80);
    send_sample(4, 90);
    send_sample(5, 100);
    send_sample(6, 110);
    send_sample(7, 120);

    repeat (20) @(posedge clk);

    select_probe(0, 0);
    cfg_read_reg(ADDR_PROBE_DATA, rdata);
    $display("[%0t] PROBE CH0 INPUT  = 0x%08h", $time, rdata);
    select_probe(0, 1);
    cfg_read_reg(ADDR_PROBE_DATA, rdata);
    $display("[%0t] PROBE CH0 RAWFIR = 0x%08h", $time, rdata);
    select_probe(7, 1);
    cfg_read_reg(ADDR_PROBE_DATA, rdata);
    $display("[%0t] PROBE CH7 RAWFIR = 0x%08h", $time, rdata);
    select_probe(7, 2);
    cfg_read_reg(ADDR_PROBE_DATA, rdata);
    $display("[%0t] PROBE CH7 FINAL  = 0x%08h", $time, rdata);
    select_probe(7, 3);
    cfg_read_reg(ADDR_PROBE_DATA, rdata);
    $display("[%0t] PROBE CH7 BIT    = 0x%08h", $time, rdata);

    cfg_write_reg(ADDR_MODE, 32'h0000_0002);

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

    select_probe(0, 2);
    cfg_read_reg(ADDR_PROBE_DATA, rdata);
    $display("[%0t] PROBE CH0 FINAL(BYPASS) = 0x%08h", $time, rdata);
    select_probe(7, 2);
    cfg_read_reg(ADDR_PROBE_DATA, rdata);
    $display("[%0t] PROBE CH7 FINAL(BYPASS) = 0x%08h", $time, rdata);

    repeat (20) @(posedge clk);
    $finish;
  end

  always @(posedge clk) begin
    if (out_frame_valid) begin
      $display("[%0t] OUT frame_valid=1 ch=%0d out_bit=%b",
        $time, out_channel_id, out_bit);
    end
  end

endmodule
