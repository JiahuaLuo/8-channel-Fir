module fir25_mac #(
  parameter int TAP = 25,
  parameter int DW  = 8,
  parameter int WW  = 8,
  parameter int AW  = 24
)(
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         win_valid,
  input  logic signed [DW-1:0]         x_vec [TAP],
  input  logic signed [WW-1:0]         w_vec [TAP],
  output logic                         acc_valid,
  output logic signed [AW-1:0]         acc
);

  typedef logic signed [DW+WW-1:0] mul_t;
  typedef logic signed [AW-1:0]    acc_t;

  mul_t prod_r [TAP];
  logic v0;
  acc_t sum_comb;

  // Stage 0: register products
  always_ff @(posedge clk or negedge rst_n) begin
    integer k;
    if (!rst_n) begin
      v0 <= 1'b0;
      for (k = 0; k < TAP; k = k + 1) begin
        prod_r[k] <= '0;
      end
    end else begin
      v0 <= win_valid;
      if (win_valid) begin
        for (k = 0; k < TAP; k = k + 1) begin
          prod_r[k] <= x_vec[k] * w_vec[k];
        end
      end
    end
  end

  // Combinational reduction
  always_comb begin
    integer j;
    sum_comb = '0;
    for (j = 0; j < TAP; j = j + 1) begin
      sum_comb += acc_t'(prod_r[j]);
    end
  end

  // Stage 1: register accumulated sum
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_valid <= 1'b0;
      acc       <= '0;
    end else begin
      acc_valid <= v0;
      if (v0) begin
        acc <= sum_comb;
      end
    end
  end

endmodule