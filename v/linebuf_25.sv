module linebuf_25 #(
  parameter int TAP = 25,
  parameter int DW  = 8
)(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 sample_valid,
  input  logic signed [DW-1:0] sample_data_s8,
  output logic                 win_valid,
  output logic signed [DW-1:0] x_vec [TAP]
);

  always_ff @(posedge clk or negedge rst_n) begin
    integer k;
    if (!rst_n) begin
      for (k = 0; k < TAP; k = k + 1) begin
        x_vec[k] <= '0;
      end
      win_valid <= 1'b0;
    end else begin
      win_valid <= sample_valid;
      if (sample_valid) begin
        for (k = TAP-1; k > 0; k = k - 1) begin
          x_vec[k] <= x_vec[k-1];
        end
        x_vec[0] <= sample_data_s8;
      end
    end
  end

endmodule