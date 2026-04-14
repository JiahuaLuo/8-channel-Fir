module tcn_equalizer_2ch_tdm #(
  parameter int CH  = 2,
  parameter int TAP = 25,
  parameter int DW  = 8,
  parameter int WW  = 8,
  parameter int AW  = 24
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   sample_valid,
  input  logic [$clog2(CH)-1:0]  sample_channel_id,
  input  logic [DW-1:0]          sample_data_u8,
  output logic                   sample_ready,
  input  logic                   offset_en,
  input  logic                   bypass_en,
  input  logic [4:0]             shift,
  input  logic [DW-1:0]          thresh_u8,
  input  logic                   w_we,
  input  logic [$clog2(TAP)-1:0] w_addr,
  input  logic [WW-1:0]          w_wdata_u8,
  input  logic [$clog2(TAP)-1:0] w_raddr,
  output logic [WW-1:0]          probe_weight_rdata_u8,
  output logic [CH-1:0]          out_valid,
  output logic [CH*DW-1:0]       out_data_u8_flat,
  output logic [CH-1:0]          bit_valid,
  output logic [CH-1:0]          out_bit,
  output logic [CH*DW-1:0]       probe_input_u8_flat,
  output logic [CH*DW-1:0]       probe_fir_out_u8_flat,
  output logic [CH*DW-1:0]       probe_final_out_u8_flat
);

  localparam int CTX_W = (CH > 1) ? $clog2(CH) : 1;
  localparam int BYPASS_LATENCY = tcn_cfg_pkg::TCN_LATENCY;

  logic signed [DW-1:0] sample_in_signed;
  logic                 tcn_out_valid;
  logic [CTX_W-1:0]     tcn_out_ctx_id;
  logic signed [DW-1:0] tcn_score_signed;

  logic                 bypass_valid_pipe [BYPASS_LATENCY];
  logic [CTX_W-1:0]     bypass_ctx_pipe [BYPASS_LATENCY];
  logic signed [DW-1:0] bypass_data_pipe [BYPASS_LATENCY];
  logic                 bypass_en_pipe [BYPASS_LATENCY];

  logic                 final_valid;
  logic [CTX_W-1:0]     final_ctx_id;
  logic signed [DW-1:0] final_score_signed;
  logic                 final_bit_value;

  logic [DW-1:0]        out_data_reg [CH];
  logic                 out_valid_reg [CH];
  logic                 bit_valid_reg [CH];
  logic                 bit_state_reg [CH];
  logic [DW-1:0]        probe_input_reg [CH];
  logic [DW-1:0]        probe_fir_reg [CH];
  logic [DW-1:0]        probe_final_reg [CH];

  logic signed [DW:0] sample_offset_ext;
  logic signed [DW-1:0] threshold_signed;

  assign sample_ready = 1'b1;
  assign probe_weight_rdata_u8 = '0;

  assign sample_offset_ext = $signed({1'b0, sample_data_u8}) - $signed(9'sd128);
  assign sample_in_signed = offset_en ? sample_offset_ext[DW-1:0] : $signed(sample_data_u8);
  // Threshold is interpreted as a signed two's-complement score-domain value.
  assign threshold_signed = $signed(thresh_u8);

  tcn_top_ctx #(
    .N_CTX(CH),
    .DATA_WIDTH(DW)
  ) u_tcn_top_ctx (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(sample_valid),
    .in_ctx_id(sample_channel_id),
    .sample_in(sample_in_signed),
    .out_valid(tcn_out_valid),
    .out_ctx_id(tcn_out_ctx_id),
    .sample_out(tcn_score_signed)
  );

  assign final_valid        = bypass_en_pipe[BYPASS_LATENCY-1] ? bypass_valid_pipe[BYPASS_LATENCY-1] : tcn_out_valid;
  assign final_ctx_id       = bypass_en_pipe[BYPASS_LATENCY-1] ? bypass_ctx_pipe[BYPASS_LATENCY-1]   : tcn_out_ctx_id;
  assign final_score_signed = bypass_en_pipe[BYPASS_LATENCY-1] ? bypass_data_pipe[BYPASS_LATENCY-1]  : tcn_score_signed;
  assign final_bit_value    = (final_score_signed > threshold_signed);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int s = 0; s < BYPASS_LATENCY; s++) begin
        bypass_valid_pipe[s] <= 1'b0;
        bypass_ctx_pipe[s]   <= '0;
        bypass_data_pipe[s]  <= '0;
        bypass_en_pipe[s]    <= 1'b0;
      end

      for (int ch = 0; ch < CH; ch++) begin
        out_data_reg[ch]    <= '0;
        out_valid_reg[ch]   <= 1'b0;
        bit_valid_reg[ch]   <= 1'b0;
        bit_state_reg[ch]   <= 1'b0;
        probe_input_reg[ch] <= '0;
        probe_fir_reg[ch]   <= '0;
        probe_final_reg[ch] <= '0;
      end
    end else begin
      bypass_valid_pipe[0] <= sample_valid;
      bypass_ctx_pipe[0]   <= sample_channel_id;
      bypass_data_pipe[0]  <= sample_in_signed;
      bypass_en_pipe[0]    <= bypass_en;

      for (int s = 1; s < BYPASS_LATENCY; s++) begin
        bypass_valid_pipe[s] <= bypass_valid_pipe[s-1];
        bypass_ctx_pipe[s]   <= bypass_ctx_pipe[s-1];
        bypass_data_pipe[s]  <= bypass_data_pipe[s-1];
        bypass_en_pipe[s]    <= bypass_en_pipe[s-1];
      end

      for (int ch = 0; ch < CH; ch++) begin
        out_valid_reg[ch] <= 1'b0;
        bit_valid_reg[ch] <= 1'b0;
      end

      if (sample_valid) begin
        probe_input_reg[sample_channel_id] <= sample_data_u8;
      end

      if (tcn_out_valid) begin
        probe_fir_reg[tcn_out_ctx_id] <= tcn_score_signed[DW-1:0];
      end

      if (final_valid) begin
        out_data_reg[final_ctx_id]    <= final_score_signed[DW-1:0];
        out_valid_reg[final_ctx_id]   <= 1'b1;
        bit_valid_reg[final_ctx_id]   <= 1'b1;
        bit_state_reg[final_ctx_id]   <= final_bit_value;
        probe_final_reg[final_ctx_id] <= final_score_signed[DW-1:0];
      end
    end
  end

  generate
    genvar g;
    for (g = 0; g < CH; g = g + 1) begin : gen_pack
      assign out_valid[g]                     = out_valid_reg[g];
      assign bit_valid[g]                     = bit_valid_reg[g];
      assign out_bit[g]                       = bit_state_reg[g];
      assign out_data_u8_flat[g*DW +: DW]     = out_data_reg[g];
      assign probe_input_u8_flat[g*DW +: DW]  = probe_input_reg[g];
      assign probe_fir_out_u8_flat[g*DW +: DW] = probe_fir_reg[g];
      assign probe_final_out_u8_flat[g*DW +: DW] = probe_final_reg[g];
    end
  endgenerate

  logic [4:0] unused_shift;
  logic unused_cfg;
  logic [$clog2(TAP)-1:0] unused_addr;
  logic [WW-1:0] unused_wdata;
  assign unused_shift = shift;
  assign unused_cfg = w_we;
  assign unused_addr = w_addr | w_raddr;
  assign unused_wdata = w_wdata_u8;

endmodule
