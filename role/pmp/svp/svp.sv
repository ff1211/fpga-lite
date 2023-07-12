//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// svp.sv
// 
// Description:
// Stereo vision processor. It take the phase map as input and output disparity.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.14  ff          Initial version
//****************************************************************

`timescale 1ns / 1ps

module svp #(
    parameter COLS = 1280,
    parameter MAX_DIS = 128,
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16,
    parameter BUFFER_DEPTH = 256,
    parameter ISSUE_WIDTH = 2,
    parameter MATCH_TH = 16'b00000000_10100000
)(
    input  logic                                aclk,
    input  logic                                aresetn,

    input  logic [BEAT_SIZE*DATA_WIDTH-1:0]     s_axis_tdata,
    input  logic                                s_axis_tvalid,
    output logic                                s_axis_tready,
    input  logic                                s_axis_tlast,
    
    output logic [BEAT_SIZE*DATA_WIDTH-1:0]     m_axis_tdata,
    output logic                                m_axis_tvalid,
    input  logic                                m_axis_tready,
    output logic                                m_axis_tlast
);
// Pre-calculations.
localparam BEAT_WIDTH = BEAT_SIZE * DATA_WIDTH;
localparam USER_WIDTH = (DATA_WIDTH+1)*3;

logic                                       lp_buf_wr_en;
logic                                       lp_buf_rd_en;
logic [MAX_DIS*DATA_WIDTH-1:0]              lp_buf_din;
logic                                       lp_buf_empty;
logic                                       lp_buf_pfull;
logic [MAX_DIS*DATA_WIDTH-1:0]              lp_buf_dout;

logic                                       rp_buf_wr_en;
logic                                       rp_buf_rd_en;
logic [BEAT_WIDTH:0]                        rp_buf_din;
logic                                       rp_buf_empty;
logic                                       rp_buf_pfull;
logic [BEAT_WIDTH:0]                        rp_buf_dout;

logic                                       dis_buf_wr_en;
logic                                       dis_buf_rd_en;
logic [ISSUE_WIDTH-1:0][USER_WIDTH-1:0]     dis_buf_din;
logic                                       dis_buf_empty;
logic                                       dis_buf_pfull;
logic [ISSUE_WIDTH-1:0][USER_WIDTH-1:0]     dis_buf_dout;

logic signed [DATA_WIDTH-1:0]                   compare_val [ISSUE_WIDTH-1:0];
logic [ISSUE_WIDTH-1:0][USER_WIDTH-1:0]         user_val;
logic [ISSUE_WIDTH-1:0]                         vld;

input_control #(
    .MAX_DIS        (   MAX_DIS         ),
    .BEAT_SIZE      (   BEAT_SIZE       ),
    .DATA_WIDTH     (   DATA_WIDTH      )
) input_control_inst (
    .aclk           (   aclk            ),
    .aresetn        (   aresetn         ),

    .s_axis_tdata   (   s_axis_tdata    ),
    .s_axis_tvalid  (   s_axis_tvalid   ),
    .s_axis_tready  (   s_axis_tready   ),
    .s_axis_tlast   (   s_axis_tlast    ),

    .lp_buf_wr_en   (   lp_buf_wr_en    ),
    .lp_buf_din     (   lp_buf_din      ),
    .lp_buf_pfull   (   lp_buf_pfull    ),

    .rp_buf_wr_en   (   rp_buf_wr_en    ),
    .rp_buf_din     (   rp_buf_din      ),
    .rp_buf_pfull   (   rp_buf_pfull    )
);

sync_fifo #(
    .FIFO_MEMORY_TYPE   (   "ultra" ),
    .FIFO_DEPTH         (   16      ),
    .PROG_FULL_THRESH   (   11      ),
    .DATA_WIDTH         (   MAX_DIS*DATA_WIDTH),
    .READ_MODE          (   "fwft"  ),
    .READ_LATENCY       (    0      )
) left_phase_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   lp_buf_wr_en    ),
    .rd_en  (   lp_buf_rd_en    ),
    .din    (   lp_buf_din      ),
    .dout   (   lp_buf_dout     ),

    .empty  (   lp_buf_empty    ),
    .pfull  (   lp_buf_pfull    )
);

sync_fifo #(
    .FIFO_DEPTH         (  BUFFER_DEPTH     ),
    .PROG_FULL_THRESH   (  BUFFER_DEPTH-10  ),
    .DATA_WIDTH         (  BEAT_WIDTH+1     ),
    .READ_MODE          (  "fwft"           ),
    .READ_LATENCY       (   0               )
) right_phase_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   rp_buf_wr_en    ),
    .rd_en  (   rp_buf_rd_en    ),
    .din    (   rp_buf_din      ),
    .dout   (   rp_buf_dout     ),

    .empty  (   rp_buf_empty    ),
    .pfull  (   rp_buf_pfull    )
);

stereo_match #(
    .COLS           (   COLS            ),
    .MAX_DIS        (   MAX_DIS         ),
    .BEAT_SIZE      (   BEAT_SIZE       ),
    .ISSUE_WIDTH    (   ISSUE_WIDTH     ),
    .DATA_WIDTH     (   DATA_WIDTH      ),
    .MATCH_TH       (   MATCH_TH        )
) stereo_match_inst (
    .clk            (   aclk            ),
    .rst_n          (   aresetn         ),

    .lp_buf_dout    (   lp_buf_dout     ),
    .lp_buf_empty   (   lp_buf_empty    ),
    .lp_buf_rd_en   (   lp_buf_rd_en    ),

    .rp_buf_dout    (   rp_buf_dout     ),
    .rp_buf_empty   (   rp_buf_empty    ),
    .rp_buf_rd_en   (   rp_buf_rd_en    ),

    .compare_val    (   compare_val     ),
    .user_val       (   user_val        ),
    .vld            (   vld             )
);

genvar i;
generate
    liner_interp #(
        .DATA_WIDTH(    DATA_WIDTH  ),
        .FORMAT    (    8           ),
        .USER_WIDTH(    USER_WIDTH  )
    ) liner_interp_inst (
        .clk        (   aclk        ),
        .rst_n      (   aresetn     ),
        .x_sub_x0   (   ),
        .x_sub_x1   (   ),
        .y1_sub_y0  (   ),
        .y0         (   ),
        .user_i     (   ),
        .vld_i      (   ),

        .user_o     (   ),
        .vld_o      (   ),
        .y          (   )
    );
endgenerate

sync_fifo #(
    .FIFO_DEPTH         (  BUFFER_DEPTH             ),
    .PROG_FULL_THRESH   (  BUFFER_DEPTH-10          ),
    .DATA_WIDTH         (  USER_WIDTH*ISSUE_WIDTH   ),
    .READ_MODE          (  "fwft"                   ),
    .READ_LATENCY       (   0                       )
) disparity_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   dis_buf_wr_en   ),
    .rd_en  (   dis_buf_rd_en   ),
    .din    (   dis_buf_din     ),
    .dout   (   dis_buf_dout    ),

    .empty  (   dis_buf_empty   ),
    .pfull  (   dis_buf_pfull   )
);
assign dis_buf_wr_en = vld;
assign dis_buf_din = user_val;

output_control #(
    .MAX_DIS        (   MAX_DIS         ),
    .BEAT_SIZE      (   BEAT_SIZE       ),
    .DATA_WIDTH     (   DATA_WIDTH      ),
    .USER_WIDTH     (   USER_WIDTH      ),
    .ISSUE_WIDTH    (   ISSUE_WIDTH     )
) output_control_inst (
    .aclk           (   aclk    ),
    .aresetn        (   aresetn ),

    .dis_buf_rd_en  (   dis_buf_rd_en   ),
    .dis_buf_empty  (   dis_buf_empty   ),
    .dis_buf_dout   (   dis_buf_dout    ),

    .m_axis_tdata   (   m_axis_tdata    ),
    .m_axis_tvalid  (   m_axis_tvalid   ),
    .m_axis_tready  (   m_axis_tready   ),
    .m_axis_tlast   (   m_axis_tlast    )
);

endmodule
