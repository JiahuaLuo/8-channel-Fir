module probe_mux_4ch #(
  parameter int CH = 2,
  parameter int DW = 8
)(
  input  logic [$clog2(CH)-1:0] probe_ch_sel,
  input  logic [2:0]            probe_sig_sel,
  input  logic [DW-1:0]         in_data_u8        [CH],
  input  logic [DW-1:0]         score_data_u8     [CH],
  input  logic [DW-1:0]         final_out_data_u8 [CH],
  input  logic [CH-1:0]         out_bit,
  input  logic [CH-1:0]         out_valid,
  input  logic [CH-1:0]         bit_valid,
  output logic [31:0]           probe_data
);

  always_comb begin
    probe_data = 32'd0;

    unique case (probe_sig_sel)
      3'd0: probe_data = {24'd0, in_data_u8[probe_ch_sel]};
      3'd1: probe_data = {24'd0, score_data_u8[probe_ch_sel]};
      3'd2: probe_data = {24'd0, final_out_data_u8[probe_ch_sel]};
      3'd3: probe_data = {31'd0, out_bit[probe_ch_sel]};
      3'd4: probe_data = {31'd0, out_valid[probe_ch_sel]};
      3'd5: probe_data = {31'd0, bit_valid[probe_ch_sel]};
      default: probe_data = 32'hCAFE_0000;
    endcase
  end

endmodule
