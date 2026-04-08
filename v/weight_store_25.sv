module weight_store_25 #(
  parameter int TAP = 25,
  parameter int WW  = 8
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   w_we,
  input  logic [$clog2(TAP)-1:0] w_addr,
  input  logic [WW-1:0]          w_wdata_u8,
  input  logic [$clog2(TAP)-1:0] r_addr,
  output logic [WW-1:0]          r_data,
  output logic signed [WW-1:0]   w_vec [TAP]
);

  assign r_data = w_vec[r_addr];

  always_ff @(posedge clk or negedge rst_n) begin
    integer k;
    if (!rst_n) begin
      for (k = 0; k < TAP; k = k + 1) begin
        w_vec[k] <= '0;
      end
    end else if (w_we) begin
      w_vec[w_addr] <= $signed(w_wdata_u8);
    end
  end

endmodule
