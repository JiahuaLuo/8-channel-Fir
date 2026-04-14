module tcn_top_ctx #(
  parameter int N_CTX = 2,
  parameter int DATA_WIDTH = 8
) (
  input  logic                                 clk,
  input  logic                                 rst_n,
  input  logic                                 in_valid,
  input  logic [$clog2(N_CTX)-1:0]             in_ctx_id,
  input  logic signed [DATA_WIDTH-1:0]         sample_in,
  output logic                                 out_valid,
  output logic [$clog2(N_CTX)-1:0]             out_ctx_id,
  output logic signed [DATA_WIDTH-1:0]         sample_out
);

  import tcn_cfg_pkg::*;

  logic signed [DATA_WIDTH-1:0] layer0_in [1];
  logic signed [DATA_WIDTH-1:0] layer0_out [4];
  logic signed [DATA_WIDTH-1:0] layer1_out [1];
  logic                         layer0_valid;
  logic [$clog2(N_CTX)-1:0]     layer0_ctx_id;

  assign layer0_in[0] = sample_in;

  tcn_block_ctx #(
    .N_CTX(N_CTX),
    .LAYER_IDX(0),
    .KERNEL_SIZE(get_kernel_size(0)),
    .DATA_WIDTH(DATA_WIDTH),
    .FRAC_BITS(TCN_FRAC_BITS),
    .C_IN(1),
    .C_OUT(4)
  ) u_layer0 (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .in_ctx_id(in_ctx_id),
    .data_in(layer0_in),
    .out_valid(layer0_valid),
    .out_ctx_id(layer0_ctx_id),
    .data_out(layer0_out)
  );

  tcn_block_ctx #(
    .N_CTX(N_CTX),
    .LAYER_IDX(1),
    .KERNEL_SIZE(get_kernel_size(1)),
    .DATA_WIDTH(DATA_WIDTH),
    .FRAC_BITS(TCN_FRAC_BITS),
    .C_IN(4),
    .C_OUT(1)
  ) u_layer1 (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(layer0_valid),
    .in_ctx_id(layer0_ctx_id),
    .data_in(layer0_out),
    .out_valid(out_valid),
    .out_ctx_id(out_ctx_id),
    .data_out(layer1_out)
  );

  assign sample_out = layer1_out[0];

endmodule
