module fir_equalizer_8ch #(
  parameter int CH  = 8,
  parameter int TAP = 25,
  parameter int DW  = 8,
  parameter int WW  = 8,
  parameter int AW  = 24
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic [CH-1:0]          in_valid,
  input  logic [CH*DW-1:0]       in_data_u8_flat,
  input  logic                   offset_en,
  input  logic                   bypass_en,
  input  logic [4:0]             shift,
  input  logic [DW-1:0]          thresh_u8,
  input  logic                   w_we,
  input  logic [$clog2(TAP)-1:0] w_addr,
  input  logic [WW-1:0]          w_wdata_u8,
  input  logic [$clog2(TAP)-1:0] w_raddr,
  output logic [CH-1:0]          out_valid,
  output logic [CH*DW-1:0]       out_data_u8_flat,
  output logic [CH-1:0]          probe_fir_out_valid,
  output logic [CH*DW-1:0]       probe_fir_out_data_u8_flat,
  output logic [WW-1:0]          probe_weight_rdata_u8,
  output logic [CH-1:0]          bit_valid,
  output logic [CH-1:0]          out_bit
);

  logic [DW-1:0] in_data_u8 [CH];
  logic [DW-1:0] out_data_u8 [CH];
  logic [DW-1:0] probe_fir_out_data_u8 [CH];
  logic [WW-1:0] probe_weight_rdata_u8_per_ch [CH];

  genvar g;

  generate
    for (g = 0; g < CH; g = g + 1) begin : gen_bus_map
      assign in_data_u8[g] = in_data_u8_flat[g*DW +: DW];
      assign out_data_u8_flat[g*DW +: DW] = out_data_u8[g];
      assign probe_fir_out_data_u8_flat[g*DW +: DW] = probe_fir_out_data_u8[g];
    end
  endgenerate

  generate
    for (g = 0; g < CH; g = g + 1) begin : gen_fir_lane
      fir_equalizer_with_decision #(
        .TAP(TAP),
        .DW (DW),
        .WW (WW),
        .AW (AW)
      ) u_fir_equalizer_with_decision (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .in_valid              (in_valid[g]),
        .in_data_u8            (in_data_u8[g]),
        .offset_en             (offset_en),
        .bypass_en             (bypass_en),
        .shift                 (shift),
        .thresh_u8             (thresh_u8),
        .w_we                  (w_we),
        .w_addr                (w_addr),
        .w_wdata_u8            (w_wdata_u8),
        .w_raddr               (w_raddr),
        .out_valid             (out_valid[g]),
        .out_data_u8           (out_data_u8[g]),
        .probe_fir_out_valid   (probe_fir_out_valid[g]),
        .probe_fir_out_data_u8 (probe_fir_out_data_u8[g]),
        .probe_weight_rdata_u8 (probe_weight_rdata_u8_per_ch[g]),
        .bit_valid             (bit_valid[g]),
        .out_bit               (out_bit[g])
      );
    end
  endgenerate

  assign probe_weight_rdata_u8 = probe_weight_rdata_u8_per_ch[0];

endmodule
