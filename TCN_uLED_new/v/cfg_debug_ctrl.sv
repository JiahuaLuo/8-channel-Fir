module cfg_debug_ctrl #(
  parameter int TAP = 25,
  parameter int DW  = 8,
  parameter int WW  = 8,
  parameter int CH  = 2
)(
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   ctrl_valid,
  input  logic                   ctrl_write,
  input  logic [7:0]             ctrl_addr,
  input  logic [31:0]            ctrl_wdata,
  output logic [31:0]            ctrl_rdata,
  output logic                   ctrl_rvalid,
  output logic                   ctrl_ready,
  input  logic [31:0]            probe_data,
  input  logic [WW-1:0]          weight_rdata_u8,
  output logic                   offset_en,
  output logic                   bypass_en,
  output logic [4:0]             shift,
  output logic [DW-1:0]          thresh_u8,
  output logic                   w_we,
  output logic [$clog2(TAP)-1:0] w_addr,
  output logic [WW-1:0]          w_wdata_u8,
  output logic [$clog2(TAP)-1:0] w_raddr,
  output logic [$clog2(CH)-1:0]  probe_ch_sel,
  output logic [2:0]             probe_sig_sel
);

  localparam logic [7:0] ADDR_MODE       = 8'h00;
  localparam logic [7:0] ADDR_SHIFT      = 8'h04;
  localparam logic [7:0] ADDR_THRESH     = 8'h08;
  localparam logic [7:0] ADDR_WADDR      = 8'h10;
  localparam logic [7:0] ADDR_WDATA      = 8'h14;
  localparam logic [7:0] ADDR_WCOMMIT    = 8'h18;
  localparam logic [7:0] ADDR_WREAD      = 8'h1C;
  localparam logic [7:0] ADDR_PROBE_SEL  = 8'h20;
  localparam logic [7:0] ADDR_PROBE_DATA = 8'h24;

  logic [$clog2(TAP)-1:0] w_addr_reg;
  logic [WW-1:0]          w_data_reg;

  assign ctrl_ready = 1'b1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      offset_en     <= 1'b0;
      bypass_en     <= 1'b0;
      shift         <= 5'd5;
      // Signed TCN score threshold encoded in two's complement.
      thresh_u8     <= 8'sd0;
      w_addr_reg    <= '0;
      w_data_reg    <= '0;
      w_we          <= 1'b0;
      w_addr        <= '0;
      w_wdata_u8    <= '0;
      w_raddr       <= '0;
      probe_ch_sel  <= '0;
      probe_sig_sel <= 3'd0;
      ctrl_rdata    <= 32'd0;
      ctrl_rvalid   <= 1'b0;
    end else begin
      w_we        <= 1'b0;
      ctrl_rvalid <= 1'b0;

      if (ctrl_valid) begin
        if (ctrl_write) begin
          unique case (ctrl_addr)
            ADDR_MODE: begin
              offset_en <= ctrl_wdata[0];
              bypass_en <= ctrl_wdata[1];
            end
            ADDR_SHIFT: begin
              shift <= ctrl_wdata[4:0];
            end
            ADDR_THRESH: begin
              thresh_u8 <= ctrl_wdata[7:0];
            end
            ADDR_WADDR: begin
              w_addr_reg <= ctrl_wdata[$clog2(TAP)-1:0];
              w_raddr    <= ctrl_wdata[$clog2(TAP)-1:0];
            end
            ADDR_WDATA: begin
              w_data_reg <= ctrl_wdata[WW-1:0];
            end
            ADDR_WCOMMIT: begin
              w_we       <= 1'b1;
              w_addr     <= w_addr_reg;
              w_wdata_u8 <= w_data_reg;
            end
            ADDR_PROBE_SEL: begin
              probe_ch_sel  <= ctrl_wdata[$clog2(CH)-1:0];
              probe_sig_sel <= ctrl_wdata[5:3];
            end
            default: begin
            end
          endcase
        end else begin
          ctrl_rvalid <= 1'b1;
          unique case (ctrl_addr)
            ADDR_MODE:       ctrl_rdata <= {30'd0, bypass_en, offset_en};
            ADDR_SHIFT:      ctrl_rdata <= {27'd0, shift};
            ADDR_THRESH:     ctrl_rdata <= {24'd0, thresh_u8};
            ADDR_WADDR:      ctrl_rdata <= {{(32-$clog2(TAP)){1'b0}}, w_addr_reg};
            ADDR_WDATA:      ctrl_rdata <= {{(32-WW){1'b0}}, w_data_reg};
            ADDR_WREAD:      ctrl_rdata <= {{(32-WW){1'b0}}, weight_rdata_u8};
            ADDR_PROBE_SEL:  ctrl_rdata <= {{(32-(3+$clog2(CH))){1'b0}}, probe_sig_sel, probe_ch_sel};
            ADDR_PROBE_DATA: ctrl_rdata <= probe_data;
            default:         ctrl_rdata <= 32'hDEAD_BEEF;
          endcase
        end
      end
    end
  end

endmodule
