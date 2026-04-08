`timescale 1ns/1ps

module tb_fir_equalizer_4ch;

  localparam int CH  = 4;
  localparam int TAP = 25;
  localparam int DW  = 8;
  localparam int WW  = 8;
  localparam int AW  = 24;

  logic                   clk;
  logic                   rst_n;

  logic [CH-1:0]          in_valid;
  logic [CH*DW-1:0]       in_data_u8_flat;

  logic                   offset_en;
  logic                   bypass_en;
  logic [4:0]             shift;
  logic [DW-1:0]          thresh_u8;

  logic                   w_we;
  logic [$clog2(TAP)-1:0] w_addr;
  logic [WW-1:0]          w_wdata_u8;

  logic [CH-1:0]          out_valid;
  logic [CH*DW-1:0]       out_data_u8_flat;
  logic [CH-1:0]          bit_valid;
  logic [CH-1:0]          out_bit;

  fir_equalizer_4ch #(
    .CH (CH),
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .AW (AW)
  ) dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .in_valid        (in_valid),
    .in_data_u8_flat (in_data_u8_flat),
    .offset_en       (offset_en),
    .bypass_en       (bypass_en),
    .shift           (shift),
    .thresh_u8       (thresh_u8),
    .w_we            (w_we),
    .w_addr          (w_addr),
    .w_wdata_u8      (w_wdata_u8),
    .out_valid       (out_valid),
    .out_data_u8_flat(out_data_u8_flat),
    .bit_valid       (bit_valid),
    .out_bit         (out_bit)
  );

  initial clk = 1'b0;
  always #10 clk = ~clk;

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

  task automatic send_4ch_sample(
    input int ch0,
    input int ch1,
    input int ch2,
    input int ch3
  );
    begin
      @(posedge clk);
      in_valid        <= 4'b1111;
      in_data_u8_flat <= {ch3[7:0], ch2[7:0], ch1[7:0], ch0[7:0]};

      @(posedge clk);
      in_valid        <= 4'b0000;
      in_data_u8_flat <= '0;
    end
  endtask

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_fir_equalizer_4ch);

    rst_n           = 1'b0;
    in_valid        = '0;
    in_data_u8_flat = '0;

    offset_en       = 1'b0;
    bypass_en       = 1'b0;
    shift           = 5'd5;
    thresh_u8       = 8'd128;

    w_we            = 1'b0;
    w_addr          = '0;
    w_wdata_u8      = '0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;

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

    send_4ch_sample(10, 20, 30, 40);
    send_4ch_sample(20, 30, 40, 50);
    send_4ch_sample(30, 40, 50, 60);
    send_4ch_sample(40, 50, 60, 70);
    send_4ch_sample(50, 60, 70, 80);

    repeat (50) @(posedge clk);

    bypass_en = 1'b1;
    send_4ch_sample(100, 110, 120, 130);
    send_4ch_sample(101, 111, 121, 131);
    repeat (10) @(posedge clk);
    bypass_en = 1'b0;

    repeat (50) @(posedge clk);
    $finish;
  end

  always @(posedge clk) begin
    if (out_valid[0]) $display("[%0t] CH0 out_valid=1 out_data=%0d", $time, out_data_u8_flat[7:0]);
    if (out_valid[1]) $display("[%0t] CH1 out_valid=1 out_data=%0d", $time, out_data_u8_flat[15:8]);
    if (out_valid[2]) $display("[%0t] CH2 out_valid=1 out_data=%0d", $time, out_data_u8_flat[23:16]);
    if (out_valid[3]) $display("[%0t] CH3 out_valid=1 out_data=%0d", $time, out_data_u8_flat[31:24]);

    if (bit_valid[0]) $display("[%0t] CH0 bit_valid=1 out_bit=%0d", $time, out_bit[0]);
    if (bit_valid[1]) $display("[%0t] CH1 bit_valid=1 out_bit=%0d", $time, out_bit[1]);
    if (bit_valid[2]) $display("[%0t] CH2 bit_valid=1 out_bit=%0d", $time, out_bit[2]);
    if (bit_valid[3]) $display("[%0t] CH3 bit_valid=1 out_bit=%0d", $time, out_bit[3]);
  end

endmodule
