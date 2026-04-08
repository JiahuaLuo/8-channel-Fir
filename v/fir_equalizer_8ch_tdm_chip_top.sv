`ifndef FIR_EQUALIZER_8CH_TDM_CHIP_TOP_SV
`define FIR_EQUALIZER_8CH_TDM_CHIP_TOP_SV

module fir_equalizer_8ch_tdm_chip_top #(
  parameter int CH  = 8,
  parameter int TAP = 25,
  parameter int DW  = 8,
  parameter int WW  = 8,
  parameter int AW  = 24
)(
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   sample_valid,
  input  logic [$clog2(CH)-1:0]  sample_channel_id,
  input  logic [DW-1:0]          sample_data,
  output logic                   sample_ready,

  input  logic                   cfg_valid,
  input  logic                   cfg_write,
  output logic                   cfg_ready,
  input  logic [3:0]             cfg_data,
  output logic                   cfg_resp_valid,
  output logic [3:0]             cfg_resp_data,

  output logic [CH-1:0]          out_bit,
  output logic                   out_frame_valid,
  output logic [$clog2(CH)-1:0]  out_channel_id
);

  logic                   ctrl_link_valid;
  logic                   ctrl_link_write;
  logic [7:0]             ctrl_link_addr;
  logic [31:0]            ctrl_link_wdata;
  logic [31:0]            ctrl_link_rdata;
  logic                   ctrl_link_rvalid;
  logic                   ctrl_link_ready;

  logic                   data_link_valid;
  logic [10:0]            data_link_data;
  logic                   data_link_ready;

  logic [CH-1:0]          out_valid;
  logic [CH*DW-1:0]       out_data_u8_flat;
  logic [CH-1:0]          bit_valid;
  logic [CH-1:0]          out_bit_int;
  integer                 i;

  assign data_link_valid = sample_valid;
  assign data_link_data  = {sample_channel_id, sample_data};
  assign sample_ready    = data_link_ready;

  cfg_nibble_adapter u_cfg_nibble_adapter (
    .clk            (clk),
    .rst_n          (rst_n),
    .cfg_valid      (cfg_valid),
    .cfg_write      (cfg_write),
    .cfg_ready      (cfg_ready),
    .cfg_data       (cfg_data),
    .cfg_resp_valid (cfg_resp_valid),
    .cfg_resp_data  (cfg_resp_data),
    .ctrl_link_valid(ctrl_link_valid),
    .ctrl_link_write(ctrl_link_write),
    .ctrl_link_addr (ctrl_link_addr),
    .ctrl_link_wdata(ctrl_link_wdata),
    .ctrl_link_rdata(ctrl_link_rdata),
    .ctrl_link_rvalid(ctrl_link_rvalid),
    .ctrl_link_ready(ctrl_link_ready)
  );

  fir_equalizer_8ch_tdm_bsg_top #(
    .CH (CH),
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .AW (AW)
  ) u_core (
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
    .out_bit         (out_bit_int)
  );

  always_comb begin
    out_channel_id = '0;
    // The current core emits at most one bit_valid per beat, so a simple
    // encoder is enough to identify which channel produced out_frame_valid.
    for (i = 0; i < CH; i = i + 1) begin
      if (bit_valid[i]) begin
        out_channel_id = i[$clog2(CH)-1:0];
      end
    end
  end

  assign out_bit         = out_bit_int;
  assign out_frame_valid = |bit_valid;

endmodule

`endif
