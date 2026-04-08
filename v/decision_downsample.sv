module decision_downsample #(
  parameter int DW = 8
)(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          out_valid,
  input  logic [DW-1:0] out_data_u8,
  input  logic [DW-1:0] thresh_u8,
  output logic          bit_valid,
  output logic          out_bit
);

  logic toggle_2x;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      toggle_2x <= 1'b0;
      bit_valid <= 1'b0;
      out_bit   <= 1'b0;
    end else begin
      bit_valid <= 1'b0;

      if (out_valid) begin
        if (!toggle_2x) begin
          toggle_2x <= 1'b1;
        end else begin
          out_bit   <= (out_data_u8 > thresh_u8);
          bit_valid <= 1'b1;
          toggle_2x <= 1'b0;
        end
      end
    end
  end

endmodule