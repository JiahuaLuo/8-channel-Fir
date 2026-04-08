module fir_equalizer_with_decision #(
  parameter int TAP = 25,
  parameter int DW  = 8,
  parameter int WW  = 8,
  parameter int AW  = 24
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   in_valid,
  input  logic [DW-1:0]          in_data_u8,
  input  logic                   offset_en,
  input  logic                   bypass_en,
  input  logic [4:0]             shift,
  input  logic [DW-1:0]          thresh_u8,
  input  logic                   w_we,
  input  logic [$clog2(TAP)-1:0] w_addr,
  input  logic [WW-1:0]          w_wdata_u8,
  input  logic [$clog2(TAP)-1:0] w_raddr,
  output logic                   out_valid,
  output logic [DW-1:0]          out_data_u8,
  output logic                   probe_fir_out_valid,
  output logic [DW-1:0]          probe_fir_out_data_u8,
  output logic [WW-1:0]          probe_weight_rdata_u8,
  output logic                   bit_valid,
  output logic                   out_bit
);

  typedef logic signed [DW-1:0] s8_t;
  typedef logic signed [AW-1:0] acc_t;

  logic sample_valid;
  logic win_valid;
  s8_t  sample_data_s8;
  s8_t  x_vec [TAP];
  s8_t  w_vec [TAP];

  logic acc_valid;
  logic fir_out_valid;
  logic [DW-1:0] fir_out_data_u8;
  acc_t acc;

  // Input adaptation
  sample_adapter #(
    .DW(DW)
  ) u_sample_adapter (
    .clk           (clk),
    .rst_n         (rst_n),
    .in_valid      (in_valid),
    .in_data_u8    (in_data_u8),
    .offset_en     (offset_en),
    .sample_valid  (sample_valid),
    .sample_data_s8(sample_data_s8)
  );

  // Line buffer
  linebuf_25 #(
    .TAP(TAP),
    .DW (DW)
  ) u_linebuf_25 (
    .clk           (clk),
    .rst_n         (rst_n),
    .sample_valid  (sample_valid),
    .sample_data_s8(sample_data_s8),
    .win_valid     (win_valid),
    .x_vec         (x_vec)
  );

  // Weight store
  weight_store_25 #(
    .TAP(TAP),
    .WW(WW)
  ) u_weight_store_25 (
    .clk       (clk),
    .rst_n     (rst_n),
    .w_we      (w_we),
    .w_addr    (w_addr),
    .w_wdata_u8(w_wdata_u8),
    .r_addr    (w_raddr),
    .r_data    (probe_weight_rdata_u8),
    .w_vec     (w_vec)
  );

  // FIR MAC
  fir25_mac #(
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .AW (AW)
  ) u_fir25_mac (
    .clk      (clk),
    .rst_n    (rst_n),
    .win_valid(win_valid),
    .x_vec    (x_vec),
    .w_vec    (w_vec),
    .acc_valid(acc_valid),
    .acc      (acc)
  );

  // Requant + saturation
  requant_sat #(
    .DW(DW),
    .AW(AW)
  ) u_requant_sat (
    .clk        (clk),
    .rst_n      (rst_n),
    .acc_valid  (acc_valid),
    .acc        (acc),
    .shift      (shift),
    .out_valid  (fir_out_valid),
    .out_data_u8(fir_out_data_u8)
  );

  assign probe_fir_out_valid   = fir_out_valid;
  assign probe_fir_out_data_u8 = fir_out_data_u8;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid   <= 1'b0;
      out_data_u8 <= '0;
    end else begin
      if (bypass_en) begin
        out_valid   <= in_valid;
        out_data_u8 <= in_data_u8;
      end else begin
        out_valid   <= fir_out_valid;
        out_data_u8 <= fir_out_data_u8;
      end
    end
  end

  // Final decision / downsample: 1 bit per 2 FIR outputs => 12.5 MHz
  decision_downsample #(
    .DW(DW)
  ) u_decision_downsample (
    .clk        (clk),
    .rst_n      (rst_n),
    .out_valid  (out_valid),
    .out_data_u8(out_data_u8),
    .thresh_u8  (thresh_u8),
    .bit_valid  (bit_valid),
    .out_bit    (out_bit)
  );

endmodule
