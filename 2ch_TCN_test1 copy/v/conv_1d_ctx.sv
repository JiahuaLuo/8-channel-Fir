module conv_1d_ctx #(
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

  localparam int CTX_W = (N_CTX > 1) ? $clog2(N_CTX) : 1;
  localparam int HIST_LEN = (KERNEL_SIZE > 1) ? (KERNEL_SIZE - 1) : 1;
  localparam int NUM_SUMS = (C_IN * KERNEL_SIZE > 0) ? (C_IN * KERNEL_SIZE) : 1;
  localparam int ACC_WIDTH = 2 * DATA_WIDTH + $clog2(NUM_SUMS) + 2;

  logic signed [DATA_WIDTH-1:0] history [N_CTX][C_IN][HIST_LEN];
  logic signed [DATA_WIDTH-1:0] data_next [C_OUT];

  function automatic logic signed [DATA_WIDTH-1:0] clamp_to_data(
    input logic signed [ACC_WIDTH-1:0] value
  );
    logic signed [ACC_WIDTH-1:0] max_pos;
    logic signed [ACC_WIDTH-1:0] min_neg;
    begin
      max_pos = (1 <<< (DATA_WIDTH - 1)) - 1;
      min_neg = -(1 <<< (DATA_WIDTH - 1));

      if (value > max_pos)
        clamp_to_data = max_pos[DATA_WIDTH-1:0];
      else if (value < min_neg)
        clamp_to_data = min_neg[DATA_WIDTH-1:0];
      else
        clamp_to_data = value[DATA_WIDTH-1:0];
    end
  endfunction

  always_comb begin
    for (int co = 0; co < C_OUT; co++) begin
      logic signed [ACC_WIDTH-1:0] acc;
      logic signed [ACC_WIDTH-1:0] scaled;
      logic signed [DATA_WIDTH-1:0] tap_value;

      acc = '0;
      for (int ci = 0; ci < C_IN; ci++) begin
        for (int k = 0; k < KERNEL_SIZE; k++) begin
          if (k == 0)
            tap_value = data_in[ci];
          else
            tap_value = history[in_ctx_id][ci][k-1];

          acc = acc + ($signed(tap_value) * $signed(tcn_cfg_pkg::get_weight(LAYER_IDX, co, ci, k)));
        end
      end

      if (FRAC_BITS > 0)
        scaled = (acc + (1 <<< (FRAC_BITS - 1))) >>> FRAC_BITS;
      else
        scaled = acc;

      data_next[co] = clamp_to_data(scaled);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_valid  <= 1'b0;
      out_ctx_id <= '0;

      for (int ctx = 0; ctx < N_CTX; ctx++) begin
        for (int ci = 0; ci < C_IN; ci++) begin
          for (int h = 0; h < HIST_LEN; h++) begin
            history[ctx][ci][h] <= '0;
          end
        end
      end

      for (int co = 0; co < C_OUT; co++) begin
        data_out[co] <= '0;
      end
    end else begin
      out_valid <= 1'b0;

      if (in_valid) begin
        out_valid  <= 1'b1;
        out_ctx_id <= in_ctx_id;

        for (int co = 0; co < C_OUT; co++) begin
          data_out[co] <= data_next[co];
        end

        for (int ci = 0; ci < C_IN; ci++) begin
          if (KERNEL_SIZE > 1) begin
            history[in_ctx_id][ci][0] <= data_in[ci];
            for (int h = 1; h < HIST_LEN; h++) begin
              history[in_ctx_id][ci][h] <= history[in_ctx_id][ci][h-1];
            end
          end
        end
      end
    end
  end

endmodule
