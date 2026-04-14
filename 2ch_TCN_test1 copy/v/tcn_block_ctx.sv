module tcn_block_ctx #(
  parameter int N_CTX = 2,
  parameter int LAYER_IDX = 0,
  parameter int KERNEL_SIZE = 4,
  parameter int DATA_WIDTH = 8,
  parameter int FRAC_BITS = 4,
  parameter int C_IN = 1,
  parameter int C_OUT = 1
) (
  input  logic                                 clk,
  input  logic                                 rst_n,
  input  logic                                 in_valid,
  input  logic [$clog2(N_CTX)-1:0]             in_ctx_id,
  input  logic signed [DATA_WIDTH-1:0]         data_in [C_IN],
  output logic                                 out_valid,
  output logic [$clog2(N_CTX)-1:0]             out_ctx_id,
  output logic signed [DATA_WIDTH-1:0]         data_out [C_OUT]
);

  logic signed [DATA_WIDTH-1:0] conv_out [C_OUT];

  conv_1d_ctx #(
    .N_CTX(N_CTX),
    .LAYER_IDX(LAYER_IDX),
    .KERNEL_SIZE(KERNEL_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .FRAC_BITS(FRAC_BITS),
    .C_IN(C_IN),
    .C_OUT(C_OUT)
  ) u_conv_1d_ctx (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .in_ctx_id(in_ctx_id),
    .data_in(data_in),
    .out_valid(out_valid),
    .out_ctx_id(out_ctx_id),
    .data_out(conv_out)
  );

  generate
    genvar g;
    for (g = 0; g < C_OUT; g++) begin : gen_relu
      assign data_out[g] = conv_out[g][DATA_WIDTH-1] ? '0 : conv_out[g];
    end
  endgenerate

endmodule
