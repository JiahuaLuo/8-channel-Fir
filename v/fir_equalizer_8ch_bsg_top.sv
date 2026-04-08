`include "fir_equalizer_8ch_tdm.sv"
`include "fir_equalizer_8ch_tdm_bsg_top.sv"

module fir_equalizer_8ch_bsg_top #(
  parameter int CH  = 8,
  parameter int TAP = 25,
  parameter int DW  = 8,
  parameter int WW  = 8,
  parameter int AW  = 24
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   data_link_valid,
  input  logic [CH*DW-1:0]       data_link_data,
  output logic                   data_link_ready,
  input  logic                   ctrl_link_valid,
  input  logic                   ctrl_link_write,
  input  logic [7:0]             ctrl_link_addr,
  input  logic [31:0]            ctrl_link_wdata,
  output logic [31:0]            ctrl_link_rdata,
  output logic                   ctrl_link_rvalid,
  output logic                   ctrl_link_ready,
  output logic [CH-1:0]          out_valid,
  output logic [CH*DW-1:0]       out_data_u8_flat,
  output logic [CH-1:0]          bit_valid,
  output logic [CH-1:0]          out_bit
);

  logic                   offset_en;
  logic                   bypass_en;
  logic [4:0]             shift;
  logic [DW-1:0]          thresh_u8;
  logic                   w_we;
  logic [$clog2(TAP)-1:0] w_addr;
  logic [$clog2(TAP)-1:0] w_raddr;
  logic [WW-1:0]          w_wdata_u8;
  logic [$clog2(CH)-1:0]  probe_ch_sel;
  logic [2:0]             probe_sig_sel;
  logic [31:0]            probe_data;
  logic [CH-1:0]          in_valid;
  logic [DW-1:0]          in_data_u8 [CH];
  logic [CH-1:0]          probe_fir_out_valid;
  logic [CH*DW-1:0]       probe_fir_out_data_u8_flat;
  logic [WW-1:0]          probe_weight_rdata_u8;
  logic [DW-1:0]          raw_fir_out_data_u8 [CH];
  logic [DW-1:0]          final_out_data_u8 [CH];
  logic [DW-1:0]          last_in_data_u8 [CH];
  logic [DW-1:0]          last_raw_fir_out_u8 [CH];
  logic [DW-1:0]          last_final_out_u8 [CH];
  logic                   last_out_bit [CH];
  logic                   seen_out_valid [CH];
  logic                   seen_bit_valid [CH];

  genvar g;
  generate
    for (g = 0; g < CH; g = g + 1) begin : gen_map
      assign in_valid[g] = data_link_valid;
      assign in_data_u8[g] = data_link_data[g*DW +: DW];
      assign raw_fir_out_data_u8[g] = probe_fir_out_data_u8_flat[g*DW +: DW];
      assign final_out_data_u8[g] = out_data_u8_flat[g*DW +: DW];
    end
  endgenerate

  assign data_link_ready = 1'b1;

  cfg_debug_ctrl #(
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .CH (CH)
  ) u_cfg_debug_ctrl (
    .clk            (clk),
    .rst_n          (rst_n),
    .ctrl_valid     (ctrl_link_valid),
    .ctrl_write     (ctrl_link_write),
    .ctrl_addr      (ctrl_link_addr),
    .ctrl_wdata     (ctrl_link_wdata),
    .ctrl_rdata     (ctrl_link_rdata),
    .ctrl_rvalid    (ctrl_link_rvalid),
    .ctrl_ready     (ctrl_link_ready),
    .probe_data     (probe_data),
    .weight_rdata_u8(probe_weight_rdata_u8),
    .offset_en      (offset_en),
    .bypass_en      (bypass_en),
    .shift          (shift),
    .thresh_u8      (thresh_u8),
    .w_we           (w_we),
    .w_addr         (w_addr),
    .w_wdata_u8     (w_wdata_u8),
    .w_raddr        (w_raddr),
    .probe_ch_sel   (probe_ch_sel),
    .probe_sig_sel  (probe_sig_sel)
  );

  fir_equalizer_8ch #(
    .CH (CH),
    .TAP(TAP),
    .DW (DW),
    .WW (WW),
    .AW (AW)
  ) u_fir_equalizer_8ch (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .in_valid               (in_valid),
    .in_data_u8_flat        (data_link_data),
    .offset_en              (offset_en),
    .bypass_en              (bypass_en),
    .shift                  (shift),
    .thresh_u8              (thresh_u8),
    .w_we                   (w_we),
    .w_addr                 (w_addr),
    .w_wdata_u8             (w_wdata_u8),
    .w_raddr                (w_raddr),
    .out_valid              (out_valid),
    .out_data_u8_flat       (out_data_u8_flat),
    .probe_fir_out_valid    (probe_fir_out_valid),
    .probe_fir_out_data_u8_flat(probe_fir_out_data_u8_flat),
    .probe_weight_rdata_u8  (probe_weight_rdata_u8),
    .bit_valid              (bit_valid),
    .out_bit                (out_bit)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    integer i;
    if (!rst_n) begin
      for (i = 0; i < CH; i = i + 1) begin
        last_out_bit[i]        <= 1'b0;
        seen_out_valid[i]      <= 1'b0;
        seen_bit_valid[i]      <= 1'b0;
        last_in_data_u8[i]     <= '0;
        last_raw_fir_out_u8[i] <= '0;
        last_final_out_u8[i]   <= '0;
      end
    end else begin
      if (data_link_valid) begin
        for (i = 0; i < CH; i = i + 1) begin
          last_in_data_u8[i] <= in_data_u8[i];
        end
      end

      for (i = 0; i < CH; i = i + 1) begin
        if (probe_fir_out_valid[i]) begin
          last_raw_fir_out_u8[i] <= raw_fir_out_data_u8[i];
        end
        if (out_valid[i]) begin
          last_final_out_u8[i] <= final_out_data_u8[i];
          seen_out_valid[i]    <= 1'b1;
        end
        if (bit_valid[i]) begin
          last_out_bit[i]   <= out_bit[i];
          seen_bit_valid[i] <= 1'b1;
        end
      end
    end
  end

  probe_mux_4ch #(
    .CH(CH),
    .DW(DW)
  ) u_probe_mux_8ch (
    .probe_ch_sel        (probe_ch_sel),
    .probe_sig_sel       (probe_sig_sel),
    .in_data_u8          (last_in_data_u8),
    .fir_out_data_u8     (last_raw_fir_out_u8),
    .final_out_data_u8   (last_final_out_u8),
    .out_bit             (last_out_bit),
    .out_valid           (seen_out_valid),
    .bit_valid           (seen_bit_valid),
    .probe_data          (probe_data)
  );

endmodule
