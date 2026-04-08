module sample_adapter #(
  parameter int DW = 8
)(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 in_valid,
  input  logic [DW-1:0]        in_data_u8,
  input  logic                 offset_en,
  output logic                 sample_valid,
  output logic signed [DW-1:0] sample_data_s8
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_valid   <= 1'b0;
      sample_data_s8 <= '0;
    end else begin
      sample_valid <= in_valid;
      if (in_valid) begin
        if (offset_en)
          sample_data_s8 <= $signed({1'b0, in_data_u8}) - 9'sd128;
        else
          sample_data_s8 <= $signed(in_data_u8);
      end
    end
  end

endmodule