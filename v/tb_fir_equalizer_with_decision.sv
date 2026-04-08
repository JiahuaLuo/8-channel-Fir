`timescale 1ns/1ps

module tb_fir_equalizer_with_decision;

  localparam int TAP = 25;
  localparam int DW  = 8;
  localparam int WW  = 8;
  localparam int AW  = 24;

  logic clk;
  logic rst_n;

  logic                   in_valid;
  logic [DW-1:0]          in_data_u8;
  logic                   offset_en;
  logic                   bypass_en;
  logic [4:0]             shift;
  logic [DW-1:0]          thresh_u8;

  logic                   w_we;
  logic [$clog2(TAP)-1:0] w_addr;
  logic [WW-1:0]          w_wdata_u8;

  logic                   out_valid;
  logic [DW-1:0]          out_data_u8;
  logic                   bit_valid;
  logic                   out_bit;

  // DUT
  fir_equalizer_with_decision #(
    .TAP(TAP),
    .DW(DW),
    .WW(WW),
    .AW(AW)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_valid   (in_valid),
    .in_data_u8 (in_data_u8),
    .offset_en  (offset_en),
    .bypass_en  (bypass_en),
    .shift      (shift),
    .thresh_u8  (thresh_u8),
    .w_we       (w_we),
    .w_addr     (w_addr),
    .w_wdata_u8 (w_wdata_u8),
    .out_valid  (out_valid),
    .out_data_u8(out_data_u8),
    .bit_valid  (bit_valid),
    .out_bit    (out_bit)
  );

  // 50 MHz clock => 20 ns period
  initial clk = 1'b0;
  always #10 clk = ~clk;

  // --------------------------
  // helper: write weight
  // --------------------------
  task automatic write_weight(input int addr, input int value);
    begin
      @(posedge clk);
      w_we       <= 1'b1;
      w_addr     <= addr[$clog2(TAP)-1:0];
      w_wdata_u8 <= value[WW-1:0];

      @(posedge clk);
      w_we       <= 1'b0;
      w_addr     <= '0;
      w_wdata_u8 <= '0;
    end
  endtask

  // --------------------------
  // helper: send one sample
  // --------------------------
  task automatic send_sample(input int value);
    begin
      @(posedge clk);
      in_valid   <= 1'b1;
      in_data_u8 <= value[DW-1:0];

      @(posedge clk);
      in_valid   <= 1'b0;
      in_data_u8 <= '0;
    end
  endtask

  integer i;

  initial begin
    // 你如果用 Verdi 看波形，建议用 FSDB
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_fir_equalizer_with_decision);

    // init
    rst_n       = 1'b0;
    in_valid    = 1'b0;
    in_data_u8  = '0;
    offset_en   = 1'b0;
    bypass_en   = 1'b0;
    shift       = 5'd5;      // 25-tap 更推荐测试时先加一点缩放
    thresh_u8   = 8'd128;

    w_we        = 1'b0;
    w_addr      = '0;
    w_wdata_u8  = '0;

    // reset
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    // -----------------------------------
    // Case 1: 25-tap symmetric positive weights
    // -----------------------------------
    write_weight(0,  8'd1);
    write_weight(1,  8'd1);
    write_weight(2,  8'd1);
    write_weight(3,  8'd2);
    write_weight(4,  8'd2);
    write_weight(5,  8'd3);
    write_weight(6,  8'd3);
    write_weight(7,  8'd4);
    write_weight(8,  8'd4);
    write_weight(9,  8'd5);
    write_weight(10, 8'd6);
    write_weight(11, 8'd7);
    write_weight(12, 8'd8);
    write_weight(13, 8'd7);
    write_weight(14, 8'd6);
    write_weight(15, 8'd5);
    write_weight(16, 8'd4);
    write_weight(17, 8'd4);
    write_weight(18, 8'd3);
    write_weight(19, 8'd3);
    write_weight(20, 8'd2);
    write_weight(21, 8'd2);
    write_weight(22, 8'd1);
    write_weight(23, 8'd1);
    write_weight(24, 8'd1);

    // send input samples
    send_sample(8'd10);
    send_sample(8'd20);
    send_sample(8'd30);
    send_sample(8'd40);
    send_sample(8'd50);
    send_sample(8'd60);
    send_sample(8'd70);
    send_sample(8'd80);

    repeat (40) @(posedge clk);

    // -----------------------------------
    // Case 2: bypass mode
    // -----------------------------------
    bypass_en = 1'b1;
    send_sample(8'd100);
    send_sample(8'd110);
    send_sample(8'd120);
    repeat (10) @(posedge clk);
    bypass_en = 1'b0;

    repeat (40) @(posedge clk);
    $finish;
  end

  // console print
  always @(posedge clk) begin
    if (out_valid) begin
      $display("[%0t] out_valid=1 out_data_u8=%0d", $time, out_data_u8);
    end
    if (bit_valid) begin
      $display("[%0t] bit_valid=1 out_bit=%0d", $time, out_bit);
    end
  end

endmodule