`ifndef FIR_EQUALIZER_8CH_TDM_BSG_TOP_SV
`define FIR_EQUALIZER_8CH_TDM_BSG_TOP_SV

module fir_equalizer_8ch_tdm_bsg_top #(
  parameter int CH  = 8,
  parameter int TAP = 25,
  parameter int DW  = 8,
  parameter int WW  = 8,
  parameter int AW  = 24
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   data_link_valid,
  input  logic [10:0]            data_link_data,
  output logic                   data_link_ready,
  input  logic                   ctrl_link_valid,
  input  logic                   ctrl_link_write,
  input  logic [7:0]             ctrl_link_addr,
  input  logic [31:0]            ctrl_link_wdata,
  output logic [31:0]            ctrl_link_rdata,
  output logic                   ctrl_link_rvalid,
  output logic                   ctrl_link_ready,
  output logic [CH-1:0]          out_valid,
  output logic [CH*DW-1:0]       out_data_u8_flat,
  output logic [CH-1:0]          bit_valid,
  output logic [CH-1:0]          out_bit
);

  logic [$clog2(CH)-1:0]  sample_channel_id;
  logic [DW-1:0]          sample_data_u8;
  logic                   sample_valid;
  logic                   sample_ready;

  logic                   offset_en;
  logic                   bypass_en;
  logic [4:0]             shift;
  logic [DW-1:0]          thresh_u8;
  logic                   w_we;
  logic [$clog2(TAP)-1:0] w_addr;
  logic [$clog2(TAP)-1:0] w_raddr;
  logic [WW-1:0]          w_wdata_u8;
  logic [WW-1:0]          weight_rdata_u8;
  logic [$clog2(CH)-1:0]  probe_ch_sel;
  logic [2:0]             probe_sig_sel;
  logic [31:0]            probe_data;
  logic [CH*DW-1:0]       probe_input_u8_flat;
  logic [CH*DW-1:0]       probe_fir_out_u8_flat;
  logic [CH*DW-1:0]       probe_final_out_u8_flat;
  logic [DW-1:0]          probe_input_arr [CH];
  logic [DW-1:0]          probe_fir_arr [CH];
  logic [DW-1:0]          probe_final_arr [CH];

  assign sample_channel_id = data_link_data[10:8];
  assign sample_data_u8    = data_link_data[7:0];
  assign sample_valid      = data_link_valid;
  assign data_link_ready   = sample_ready;

  generate
    genvar g;
    for (g = 0; g < CH; g = g + 1) begin : gen_probe_unpack
      assign probe_input_arr[g] = probe_input_u8_flat[g*DW +: DW];
      assign probe_fir_arr[g]   = probe_fir_out_u8_flat[g*DW +: DW];
      assign probe_final_arr[g] = probe_final_out_u8_flat[g*DW +: DW];
    end
  endgenerate

  cfg_debug_ctrl #(
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .CH (CH)
  ) u_cfg_debug_ctrl (
    .clk            (clk),
    .rst_n          (rst_n),
    .ctrl_valid     (ctrl_link_valid),
    .ctrl_write     (ctrl_link_write),
    .ctrl_addr      (ctrl_link_addr),
    .ctrl_wdata     (ctrl_link_wdata),
    .ctrl_rdata     (ctrl_link_rdata),
    .ctrl_rvalid    (ctrl_link_rvalid),
    .ctrl_ready     (ctrl_link_ready),
    .probe_data     (probe_data),
    .weight_rdata_u8(weight_rdata_u8),
    .offset_en      (offset_en),
    .bypass_en      (bypass_en),
    .shift          (shift),
    .thresh_u8      (thresh_u8),
    .w_we           (w_we),
    .w_addr         (w_addr),
    .w_wdata_u8     (w_wdata_u8),
    .w_raddr        (w_raddr),
    .probe_ch_sel   (probe_ch_sel),
    .probe_sig_sel  (probe_sig_sel)
  );

  fir_equalizer_8ch_tdm #(
    .CH (CH),
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .AW (AW)
  ) u_fir_equalizer_8ch_tdm (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .sample_valid          (sample_valid),
    .sample_channel_id     (sample_channel_id),
    .sample_data_u8        (sample_data_u8),
    .sample_ready          (sample_ready),
    .offset_en             (offset_en),
    .bypass_en             (bypass_en),
    .shift                 (shift),
    .thresh_u8             (thresh_u8),
    .w_we                  (w_we),
    .w_addr                (w_addr),
    .w_wdata_u8            (w_wdata_u8),
    .w_raddr               (w_raddr),
    .probe_weight_rdata_u8 (weight_rdata_u8),
    .out_valid             (out_valid),
    .out_data_u8_flat      (out_data_u8_flat),
    .bit_valid             (bit_valid),
    .out_bit               (out_bit),
    .probe_input_u8_flat   (probe_input_u8_flat),
    .probe_fir_out_u8_flat (probe_fir_out_u8_flat),
    .probe_final_out_u8_flat(probe_final_out_u8_flat)
  );

  probe_mux_4ch #(
    .CH(CH),
    .DW(DW)
  ) u_probe_mux (
    .probe_ch_sel        (probe_ch_sel),
    .probe_sig_sel       (probe_sig_sel),
    .in_data_u8          (probe_input_arr),
    .fir_out_data_u8     (probe_fir_arr),
    .final_out_data_u8   (probe_final_arr),
    .out_bit             (out_bit),
    .out_valid           (out_valid),
    .bit_valid           (bit_valid),
    .probe_data          (probe_data)
  );

endmodule

`endif
