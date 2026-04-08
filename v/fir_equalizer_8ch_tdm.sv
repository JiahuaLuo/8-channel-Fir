`ifndef FIR_EQUALIZER_8CH_TDM_SV
`define FIR_EQUALIZER_8CH_TDM_SV

module fir_equalizer_8ch_tdm #(
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

  typedef logic signed [DW-1:0] s8_t;

  logic [DW-1:0] linebuf_mem [CH][TAP];
  logic [WW-1:0] weight_mem [TAP];

  logic [DW-1:0] out_data_reg [CH];
  logic          out_valid_reg [CH];
  logic          out_bit_reg [CH];
  logic          bit_valid_reg [CH];
  logic          downsample_toggle_reg [CH];

  logic [DW-1:0] probe_input_reg [CH];
  logic [DW-1:0] probe_fir_reg [CH];
  logic [DW-1:0] probe_final_reg [CH];

  s8_t x_vec [TAP];
  logic signed [WW-1:0] w_vec [TAP];
  logic                  acc_valid;
  logic signed [AW-1:0]  acc;
  logic                  fir_out_valid;
  logic [DW-1:0]         fir_out_u8;

  logic                  pipe_vld_s0;
  logic [$clog2(CH)-1:0] pipe_ch_s0;
  logic [DW-1:0]         pipe_sample_u8_s0;
  logic                  pipe_bypass_en_s0;
  logic                  pipe_vld_s1;
  logic [$clog2(CH)-1:0] pipe_ch_s1;
  logic [DW-1:0]         pipe_sample_u8_s1;
  logic                  pipe_bypass_en_s1;
  logic                  pipe_vld_s2;
  logic [$clog2(CH)-1:0] pipe_ch_s2;
  logic [DW-1:0]         pipe_sample_u8_s2;
  logic                  pipe_bypass_en_s2;

  logic [$clog2(CH)-1:0] final_ch;
  logic                  final_valid;
  logic [DW-1:0]         final_out_u8;
  logic                  final_bit;
  logic                  final_bit_valid;

  assign sample_ready = 1'b1;
  assign probe_weight_rdata_u8 = weight_mem[w_raddr];

  always_comb begin
    integer i;

    x_vec[0] = offset_en
      ? s8_t'($signed({1'b0, sample_data_u8}) - 9'sd128)
      : s8_t'(sample_data_u8);

    for (i = 1; i < TAP; i = i + 1) begin
      x_vec[i] = offset_en
        ? s8_t'($signed({1'b0, linebuf_mem[sample_channel_id][i-1]}) - 9'sd128)
        : s8_t'(linebuf_mem[sample_channel_id][i-1]);
    end

    for (i = 0; i < TAP; i = i + 1) begin
      w_vec[i] = $signed(weight_mem[i]);
    end
  end

  fir25_mac #(
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .AW (AW)
  ) u_fir25_mac (
    .clk      (clk),
    .rst_n    (rst_n),
    .win_valid(sample_valid),
    .x_vec    (x_vec),
    .w_vec    (w_vec),
    .acc_valid(acc_valid),
    .acc      (acc)
  );

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
    .out_data_u8(fir_out_u8)
  );

  assign final_ch     = pipe_ch_s2;
  assign final_valid  = pipe_vld_s2;
  assign final_out_u8 = pipe_bypass_en_s2 ? pipe_sample_u8_s2 : fir_out_u8;

  always_comb begin
    final_bit_valid = 1'b0;
    final_bit       = out_bit_reg[final_ch];

    if (final_valid) begin
      if (!downsample_toggle_reg[final_ch]) begin
        final_bit_valid = 1'b0;
        final_bit       = out_bit_reg[final_ch];
      end else begin
        final_bit_valid = 1'b1;
        final_bit       = (final_out_u8 > thresh_u8);
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    integer i;
    integer j;

    if (!rst_n) begin
      pipe_vld_s0       <= 1'b0;
      pipe_ch_s0        <= '0;
      pipe_sample_u8_s0 <= '0;
      pipe_bypass_en_s0 <= 1'b0;
      pipe_vld_s1       <= 1'b0;
      pipe_ch_s1        <= '0;
      pipe_sample_u8_s1 <= '0;
      pipe_bypass_en_s1 <= 1'b0;
      pipe_vld_s2       <= 1'b0;
      pipe_ch_s2        <= '0;
      pipe_sample_u8_s2 <= '0;
      pipe_bypass_en_s2 <= 1'b0;

      for (i = 0; i < TAP; i = i + 1) begin
        weight_mem[i] <= '0;
      end

      for (i = 0; i < CH; i = i + 1) begin
        out_data_reg[i]         <= '0;
        out_valid_reg[i]        <= 1'b0;
        out_bit_reg[i]          <= 1'b0;
        bit_valid_reg[i]        <= 1'b0;
        downsample_toggle_reg[i] <= 1'b0;
        probe_input_reg[i]      <= '0;
        probe_fir_reg[i]        <= '0;
        probe_final_reg[i]      <= '0;

        for (j = 0; j < TAP; j = j + 1) begin
          linebuf_mem[i][j] <= '0;
        end
      end
    end else begin
      pipe_vld_s0       <= sample_valid;
      pipe_ch_s0        <= sample_channel_id;
      pipe_sample_u8_s0 <= sample_data_u8;
      pipe_bypass_en_s0 <= bypass_en;

      pipe_vld_s1       <= pipe_vld_s0;
      pipe_ch_s1        <= pipe_ch_s0;
      pipe_sample_u8_s1 <= pipe_sample_u8_s0;
      pipe_bypass_en_s1 <= pipe_bypass_en_s0;

      pipe_vld_s2       <= pipe_vld_s1;
      pipe_ch_s2        <= pipe_ch_s1;
      pipe_sample_u8_s2 <= pipe_sample_u8_s1;
      pipe_bypass_en_s2 <= pipe_bypass_en_s1;

      if (w_we) begin
        weight_mem[w_addr] <= w_wdata_u8;
      end

      for (i = 0; i < CH; i = i + 1) begin
        out_valid_reg[i] <= 1'b0;
        bit_valid_reg[i] <= 1'b0;
      end

      if (sample_valid) begin
        for (j = TAP-1; j > 0; j = j - 1) begin
          linebuf_mem[sample_channel_id][j] <= linebuf_mem[sample_channel_id][j-1];
        end
        linebuf_mem[sample_channel_id][0] <= sample_data_u8;
      end

      if (final_valid) begin
        out_data_reg[final_ch]    <= final_out_u8;
        out_valid_reg[final_ch]   <= 1'b1;
        probe_input_reg[final_ch] <= pipe_sample_u8_s1;
        probe_fir_reg[final_ch]   <= fir_out_u8;
        probe_final_reg[final_ch] <= final_out_u8;
        downsample_toggle_reg[final_ch] <= ~downsample_toggle_reg[final_ch];

        if (final_bit_valid) begin
          out_bit_reg[final_ch]   <= final_bit;
          bit_valid_reg[final_ch] <= 1'b1;
        end
      end
    end
  end

  generate
    genvar g;
    for (g = 0; g < CH; g = g + 1) begin : gen_pack
      assign out_valid[g] = out_valid_reg[g];
      assign bit_valid[g] = bit_valid_reg[g];
      assign out_bit[g]   = out_bit_reg[g];

      assign out_data_u8_flat[g*DW +: DW]         = out_data_reg[g];
      assign probe_input_u8_flat[g*DW +: DW]      = probe_input_reg[g];
      assign probe_fir_out_u8_flat[g*DW +: DW]    = probe_fir_reg[g];
      assign probe_final_out_u8_flat[g*DW +: DW]  = probe_final_reg[g];
    end
  endgenerate

endmodule

`endif
