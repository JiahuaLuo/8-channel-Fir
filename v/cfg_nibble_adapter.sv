module cfg_nibble_adapter (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        cfg_valid,
  input  logic        cfg_write,
  output logic        cfg_ready,
  input  logic [3:0]  cfg_data,

  output logic        cfg_resp_valid,
  output logic [3:0]  cfg_resp_data,

  output logic        ctrl_link_valid,
  output logic        ctrl_link_write,
  output logic [7:0]  ctrl_link_addr,
  output logic [31:0] ctrl_link_wdata,
  input  logic [31:0] ctrl_link_rdata,
  input  logic        ctrl_link_rvalid,
  input  logic        ctrl_link_ready
);

  typedef enum logic [2:0] {
    IDLE,
    RECV_ADDR,
    RECV_WDATA,
    ISSUE_CMD,
    WAIT_RDATA,
    SEND_RDATA
  } state_t;

  state_t state_r;

  logic        op_write_r;
  logic [7:0]  addr_shift_r;
  logic [31:0] data_shift_r;
  logic [3:0]  nibble_count_r;
  logic [31:0] readback_shift_r;

  assign cfg_ready = (state_r == IDLE) || (state_r == RECV_ADDR) || (state_r == RECV_WDATA);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_r          <= IDLE;
      op_write_r       <= 1'b0;
      addr_shift_r     <= '0;
      data_shift_r     <= '0;
      nibble_count_r   <= '0;
      readback_shift_r <= '0;

      ctrl_link_valid  <= 1'b0;
      ctrl_link_write  <= 1'b0;
      ctrl_link_addr   <= '0;
      ctrl_link_wdata  <= '0;

      cfg_resp_valid   <= 1'b0;
      cfg_resp_data    <= '0;
    end else begin
      ctrl_link_valid <= 1'b0;
      cfg_resp_valid  <= 1'b0;

      case (state_r)
        IDLE: begin
          if (cfg_valid) begin
            op_write_r     <= cfg_write;
            addr_shift_r   <= {cfg_data, 4'h0};
            nibble_count_r <= 4'd1;
            state_r        <= RECV_ADDR;
          end
        end

        RECV_ADDR: begin
          if (cfg_valid) begin
            // The first nibble is stored in addr_shift_r[7:4], so keep that
            // upper nibble and append the second nibble into addr_shift_r[3:0].
            addr_shift_r <= {addr_shift_r[7:4], cfg_data};
            if (op_write_r) begin
              data_shift_r   <= '0;
              nibble_count_r <= '0;
              state_r        <= RECV_WDATA;
            end else begin
              state_r <= ISSUE_CMD;
            end
          end
        end

        RECV_WDATA: begin
          if (cfg_valid) begin
            data_shift_r   <= {data_shift_r[27:0], cfg_data};
            nibble_count_r <= nibble_count_r + 4'd1;
            if (nibble_count_r == 4'd7) begin
              state_r <= ISSUE_CMD;
            end
          end
        end

        ISSUE_CMD: begin
          if (ctrl_link_ready) begin
            ctrl_link_valid <= 1'b1;
            ctrl_link_write <= op_write_r;
            ctrl_link_addr  <= addr_shift_r;
            ctrl_link_wdata <= data_shift_r;

            if (op_write_r) begin
              state_r <= IDLE;
            end else begin
              state_r <= WAIT_RDATA;
            end
          end
        end

        WAIT_RDATA: begin
          if (ctrl_link_rvalid) begin
            readback_shift_r <= ctrl_link_rdata;
            nibble_count_r   <= '0;
            state_r          <= SEND_RDATA;
          end
        end

        SEND_RDATA: begin
          cfg_resp_valid   <= 1'b1;
          cfg_resp_data    <= readback_shift_r[31:28];
          readback_shift_r <= {readback_shift_r[27:0], 4'h0};
          nibble_count_r   <= nibble_count_r + 4'd1;

          if (nibble_count_r == 4'd7) begin
            state_r <= IDLE;
          end
        end

        default: begin
          state_r <= IDLE;
        end
      endcase
    end
  end

endmodule
