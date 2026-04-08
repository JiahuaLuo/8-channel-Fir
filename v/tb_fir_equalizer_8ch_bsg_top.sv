`timescale 1ns/1ps

module tb_fir_equalizer_8ch_tdm_bsg_top;

  localparam int CH  = 8;
  localparam int TAP = 25;
  localparam int DW  = 8;
  localparam int WW  = 8;
  localparam int AW  = 24;

  logic                   clk;
  logic                   rst_n;
  logic                   data_link_valid;
  logic [10:0]            data_link_data;
  logic                   data_link_ready;
  logic                   ctrl_link_valid;
  logic                   ctrl_link_write;
  logic [7:0]             ctrl_link_addr;
  logic [31:0]            ctrl_link_wdata;
  logic [31:0]            ctrl_link_rdata;
  logic                   ctrl_link_rvalid;
  logic                   ctrl_link_ready;
  logic [7:0]             last_read_addr;
  logic [CH-1:0]          out_valid;
  logic [CH*DW-1:0]       out_data_u8_flat;
  logic [CH-1:0]          bit_valid;
  logic [CH-1:0]          out_bit;

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

  task automatic send_sample(input int ch_id, input int sample);
    begin
      @(posedge clk);
      data_link_valid <= 1'b1;
      data_link_data  <= {ch_id[2:0], sample[7:0]};

      @(posedge clk);
      data_link_valid <= 1'b0;
      data_link_data  <= '0;
    end
  endtask

  task automatic select_probe(input int ch_sel, input int sig_sel);
    reg [31:0] sel_word;
    begin
      sel_word = 32'd0;
      sel_word[2:0] = ch_sel[2:0];
      sel_word[5:3] = sig_sel[2:0];
      ctrl_write_reg(ADDR_PROBE_SEL, sel_word);
    end
  endtask

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

    ctrl_write_reg(ADDR_MODE, 32'h0000_0000);
    ctrl_write_reg(ADDR_SHIFT, 32'd5);
    ctrl_write_reg(ADDR_THRESH, 32'd128);

    ctrl_read_reg(ADDR_MODE);
    ctrl_read_reg(ADDR_SHIFT);
    ctrl_read_reg(ADDR_THRESH);

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

    ctrl_write_reg(ADDR_WADDR, 32'd12);
    ctrl_read_reg(ADDR_WREAD);

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

    repeat (50) @(posedge clk);

    select_probe(0, 0);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(0, 1);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(7, 1);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(7, 2);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(7, 3);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(7, 4);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(7, 5);
    ctrl_read_reg(ADDR_PROBE_DATA);

    ctrl_write_reg(ADDR_MODE, 32'h0000_0002);
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

    repeat (20) @(posedge clk);

    select_probe(0, 1);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(0, 2);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(7, 1);
    ctrl_read_reg(ADDR_PROBE_DATA);
    select_probe(7, 2);
    ctrl_read_reg(ADDR_PROBE_DATA);

    repeat (20) @(posedge clk);
    $finish;
  end

  always @(posedge clk) begin
    integer c;
    for (c = 0; c < CH; c = c + 1) begin
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

module tb_fir_equalizer_8ch_bsg_top;
  tb_fir_equalizer_8ch_tdm_bsg_top compat();
endmodule
