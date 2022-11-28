module rel_phase_4steps #(
    parameter DATA_WIDTH = 16
) (
    input       clk,
    input       rst_n,
    input       vld_i,
    input [7:0] pixel1_i,
    input [7:0] pixel2_i,
    input [7:0] pixel3_i,
    input [7:0] pixel4_i,
    input       tlast_i,
    output                          vld_o,
    output signed [DATA_WIDTH-1:0]  phase_o,
    output                          tlast_o,
    output        [DATA_WIDTH-1:0]  mod_rate_o
);

logic signed [15:0] pixel1_r;
logic signed [15:0] pixel2_r;
logic signed [15:0] pixel3_r;
logic signed [15:0] pixel4_r;
logic signed [15:0] diff_42;
logic signed [15:0] diff_13;
logic signed [16:0] diff_42_p2;
logic signed [16:0] diff_13_p2;
logic signed [17:0] diff_p2_sum;
logic        [15:0] root_ans;
logic               root_vld;
logic signed [15:0] diff_42_norm;
logic signed [15:0] diff_13_norm;
logic signed [15:0] diff_42_norm_s;
logic signed [15:0] diff_13_norm_s;
logic [3:0] vld_i_r;
logic [3:0] tlast_i_r;
logic root_buf_wr_en;
logic root_buf_rd_en;
logic [15:0]root_buf_din;
logic [15:0]root_buf_dout;

// Buffer pixel data and shift.
// Fixed-point twos complement numbers with an integer width of 8 bits (7QN format).
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[0] <= 0;
        tlast_i_r[0] <= 0;
    end else begin
        pixel1_r <= {8'b0, pixel1_i};
        pixel2_r <= {8'b0, pixel2_i};
        pixel3_r <= {8'b0, pixel3_i};
        pixel4_r <= {8'b0, pixel4_i};
        vld_i_r[0] <= vld_i;
        tlast_i_r[0] <= tlast_i;
    end
end

// Substract.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[1] <= 0;
        tlast_i_r[1] <= 0;
    end else begin
        diff_42 <= pixel4_r - pixel2_r;
        diff_13 <= pixel1_r - pixel3_r;
        vld_i_r[1] <= vld_i_r[0];
        tlast_i_r[1] <= tlast_i_r[0];
    end
end

// Scale diff to get higher accuracy.
// Power 2.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[2] <= 0;
        tlast_i_r[2] <= 0;
    end else begin
        diff_42_norm <= diff_42 * 64;
        diff_13_norm <= diff_13 * 64;
        diff_42_p2 <= diff_42 * diff_42;
        diff_13_p2 <= diff_13 * diff_13;
        vld_i_r[2] <= vld_i_r[1];
        tlast_i_r[2] <= tlast_i_r[1];
    end
end

// Shift.
// Add.
// Fixed-point twos complement numbers with an integer width of 2 bits (1QN format).
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[3] <= 0;
        tlast_i_r[3] <= 0;
    end else begin
        diff_42_norm_s <= diff_42_norm;
        diff_13_norm_s <= diff_13_norm;
        diff_p2_sum <= diff_42_p2 + diff_13_p2;
        vld_i_r[3] <= vld_i_r[2];
        tlast_i_r[3] <= tlast_i_r[2];
    end
end

// Arc Tan.
// Delay is 20 cycles.
cordic_arctan cordic_arctan_inst (
  .aclk     (clk),
  .s_axis_cartesian_tvalid  (   vld_i_r[3]      ),
  .s_axis_cartesian_tlast   (   tlast_i_r[3]    ),
  .s_axis_cartesian_tdata   (   {diff_42_norm_s, diff_13_norm_s} ),
  .m_axis_dout_tvalid       (   vld_o       ),
  .m_axis_dout_tlast        (   tlast_o     ),
  .m_axis_dout_tdata        (   phase_o     )
);

// Square root
// Delay is 9 cycles.
cordic_sr cordic_sr_inst (
    .aclk   (clk),                                           
    .s_axis_cartesian_tvalid(   vld_i_r[3]              ),
    .s_axis_cartesian_tdata (   {7'b0, diff_p2_sum[16:0]}),
    .m_axis_dout_tvalid     (   root_vld                ),
    .m_axis_dout_tdata      (   root_ans                )
);

// Square root fifo. Used to match calculation speed difference between arctan and suqare root.
sync_fifo #(
    .FIFO_DEPTH         (   32      ),
    .DATA_WIDTH         (   16      ),
    .READ_MODE          (   "fwft"  ),
    .READ_LATENCY       (    0      )
) root_fifo (
    .clk    (   clk    ),
    .rst_n  (   rst_n  ),

    .wr_en  (   root_buf_wr_en  ),
    .rd_en  (   root_buf_rd_en  ),
    .din    (   root_buf_din    ),
    .dout   (   root_buf_dout   )
);
assign root_buf_wr_en = root_vld;
assign root_buf_rd_en = vld_o;
assign root_buf_din = {7'b0, root_ans[8:0]};

assign mod_rate_o = root_buf_dout >> 1;

endmodule