package tcn_cfg_pkg;

localparam int TCN_N_CTX = 2;
localparam int TCN_LAYERS = 2;
localparam int TCN_DATA_WIDTH = 8;
localparam int TCN_FRAC_BITS = 4;
localparam int TCN_KERNEL_SIZE = 4;
localparam int TCN_MAX_CH = 4;
localparam int TCN_LATENCY = 2;

function automatic int get_kernel_size(int idx);
  case (idx)
    0: return 4;
    1: return 4;
    default: return 0;
  endcase
endfunction

function automatic int get_dilation(int idx);
  case (idx)
    0: return 1;
    1: return 1;
    default: return 0;
  endcase
endfunction

function automatic int get_stride(int idx);
  case (idx)
    0: return 1;
    1: return 1;
    default: return 0;
  endcase
endfunction

function automatic int get_channel_size(int idx);
  case (idx)
    0: return 1;
    1: return 4;
    2: return 1;
    default: return 0;
  endcase
endfunction

function automatic logic signed [TCN_DATA_WIDTH-1:0] get_weight(
  int l,
  int co,
  int ci,
  int k
);
  logic signed [TCN_DATA_WIDTH-1:0] w;
  begin
    w = '0;

    case (l)
      0: begin
        case ({co[1:0], ci[1:0], k[1:0]})
          6'b00_00_00: w = 8'shf9;
          6'b00_00_01: w = 8'sh05;
          6'b00_00_10: w = 8'sh03;
          6'b00_00_11: w = 8'shff;

          6'b01_00_00: w = 8'shff;
          6'b01_00_01: w = 8'sh06;
          6'b01_00_10: w = 8'shf9;
          6'b01_00_11: w = 8'sh03;

          6'b10_00_00: w = 8'shfb;
          6'b10_00_01: w = 8'shf9;
          6'b10_00_10: w = 8'sh00;
          6'b10_00_11: w = 8'sh08;

          6'b11_00_00: w = 8'sh04;
          6'b11_00_01: w = 8'sh04;
          6'b11_00_10: w = 8'sh04;
          6'b11_00_11: w = 8'sh05;
          default: w = '0;
        endcase
      end

      1: begin
        case ({co[1:0], ci[1:0], k[1:0]})
          6'b00_00_00: w = 8'sh02;
          6'b00_00_01: w = 8'shfe;
          6'b00_00_10: w = 8'sh02;
          6'b00_00_11: w = 8'shfe;

          6'b00_01_00: w = 8'sh01;
          6'b00_01_01: w = 8'sh01;
          6'b00_01_10: w = 8'sh01;
          6'b00_01_11: w = 8'sh01;

          6'b00_10_00: w = 8'sh00;
          6'b00_10_01: w = 8'sh01;
          6'b00_10_10: w = 8'shff;
          6'b00_10_11: w = 8'sh01;

          6'b00_11_00: w = 8'sh00;
          6'b00_11_01: w = 8'sh00;
          6'b00_11_10: w = 8'sh00;
          6'b00_11_11: w = 8'sh00;
          default: w = '0;
        endcase
      end

      default: w = '0;
    endcase

    return w;
  end
endfunction

endpackage
