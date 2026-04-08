module requant_sat #(
  parameter int DW = 8,
  parameter int AW = 24
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   acc_valid,
  input  logic signed [AW-1:0]   acc,
  input  logic [4:0]             shift,
  output logic                   out_valid,
  output logic [DW-1:0]          out_data_u8
);

  typedef logic signed [DW-1:0] s8_t;
  typedef logic signed [AW-1:0] acc_t;

  logic signed [AW-1:0] shifted_acc;
  s8_t                  y_s8;
  logic [DW:0]          y_u9;

  function automatic s8_t sat_to_s8(input acc_t v);
    if (v > acc_t'(127))
      return s8_t'(127);
    else if (v < acc_t'(-128))
      return s8_t'(-128);
    else
      return s8_t'(v[DW-1:0]);
  endfunction

  always_comb begin
    shifted_acc = acc >>> shift;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid   <= 1'b0;
      out_data_u8 <= '0;
      y_s8        <= '0;
    end else begin
      out_valid <= acc_valid;
      if (acc_valid) begin
        y_s8        <= sat_to_s8(shifted_acc);
        y_u9        = {1'b0, sat_to_s8(shifted_acc)} + (1 << (DW-1));
        out_data_u8 <= y_u9[DW-1:0];
      end
    end
  end

endmodule