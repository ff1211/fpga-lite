//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// match_phase.sv
// 
// Description:
// Match absolute phase and output disparity.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.14  ff          Initial version
//****************************************************************

`timescale 1ns / 1ps

module match_phase #(
    parameter ROW_SIZE = 1280,
    parameter WIN_SIZE = 32,
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16,
    parameter BUFFER_DEPTH = 512,
    parameter READ_LATENCY = 2,
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
localparam CACHE_WIDTH = WIN_SIZE * DATA_WIDTH;
localparam ADDR_WIDTH = $clog2(ROW_SIZE/WIN_SIZE);

logic [BEAT_WIDTH-1:0]                  cache_axis_tdata;
logic                                   cache_axis_tvalid;
logic                                   cache_axis_tready;
logic                                   cache_axis_tlast;
logic [BEAT_SIZE-1:0][ADDR_WIDTH-1:0]   cache_addr;
logic [BEAT_SIZE-1:0][CACHE_WIDTH-1:0]  cache_dout;

logic signed [DATA_WIDTH-1:0]           abs_phase1      [BEAT_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]           abs_phase1_pos  [BEAT_SIZE-1:0];
logic                                   vld_o;
logic signed [DATA_WIDTH-1:0]           disparity       [BEAT_SIZE-1:0];
logic [BEAT_SIZE-1:0]                   vld_i;

logic                                   phase_buf_wr_en;
logic [BEAT_SIZE-1:0]                   phase_buf_rd_en;
logic [BEAT_SIZE-1:0][DATA_WIDTH*2:0]   phase_buf_din;
logic [BEAT_SIZE-1:0]                   phase_buf_empty;
logic [BEAT_SIZE-1:0]                   phase_buf_pfull;
logic [BEAT_SIZE-1:0][DATA_WIDTH*2:0]   phase_buf_dout;

logic [BEAT_SIZE-1:0]                   dis_buf_wr_en;
logic [BEAT_SIZE-1:0]                   dis_buf_rd_en;
logic [BEAT_SIZE-1:0][DATA_WIDTH:0]     dis_buf_din;
logic [BEAT_SIZE-1:0]                   dis_buf_empty;
logic [BEAT_SIZE-1:0]                   dis_buf_pfull;
logic [BEAT_SIZE-1:0][DATA_WIDTH:0]     dis_buf_dout;

control #(
    .ROW_SIZE       (   ROW_SIZE        ),
    .WIN_SIZE       (   WIN_SIZE        ),
    .BEAT_SIZE      (   BEAT_SIZE       ),
    .DATA_WIDTH     (   DATA_WIDTH      ),
    .BUFFER_DEPTH   (   BUFFER_DEPTH    )
) control_inst (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .s_axis_tdata   (   s_axis_tdata    ),
    .s_axis_tvalid  (   s_axis_tvalid   ),
    .s_axis_tready  (   s_axis_tready   ),
    .s_axis_tlast   (   s_axis_tlast    ),
    
    .m_cache_axis_tdata     (   cache_axis_tdata    ),
    .m_cache_axis_tvalid    (   cache_axis_tvalid   ),
    .m_cache_axis_tready    (   cache_axis_tready   ),
    .m_cache_axis_tlast     (   cache_axis_tlast    ),

    .phase_buf_wr_en    (   phase_buf_wr_en     ),
    .phase_buf_din      (   phase_buf_din       ),
    .phase_buf_pfull    (   phase_buf_pfull     ),

    .dis_buf_rd_en      (   dis_buf_rd_en       ),
    .dis_buf_empty      (   dis_buf_empty       ),
    .dis_buf_dout       (   dis_buf_dout        ),

    .m_axis_tdata       (   m_axis_tdata        ),
    .m_axis_tvalid      (   m_axis_tvalid       ),
    .m_axis_tready      (   m_axis_tready       ),
    .m_axis_tlast       (   m_axis_tlast        )
);

genvar i;
generate
for (i = 0; i < BEAT_SIZE; i++) begin
    sync_fifo #(
        .FIFO_DEPTH         (  BUFFER_DEPTH     ),
        .PROG_FULL_THRESH   (  BUFFER_DEPTH-10  ),
        .DATA_WIDTH         (  DATA_WIDTH*2+1   ),
        .READ_MODE          (  "fwft"           ),
        .READ_LATENCY       (   0               )
    ) phase_1_fifo_inst (
        .clk    (   aclk    ),
        .rst_n  (   aresetn ),

        .wr_en  (   phase_buf_wr_en     ),
        .rd_en  (   phase_buf_rd_en[i]  ),
        .din    (   phase_buf_din[i]    ),
        .dout   (   phase_buf_dout[i]   ),

        .empty  (   phase_buf_empty[i]  ),
        .pfull  (   phase_buf_pfull[i]  )
    );

    logic                           match_vld_o;
    logic                           not_found;
    logic signed [DATA_WIDTH-1:0]   y_sub_y1;
    logic signed [DATA_WIDTH-1:0]   y_sub_y0;
    logic signed [DATA_WIDTH-1:0]   x0;
    logic signed [DATA_WIDTH-1:0]   abs_phase1_pos_o;
    logic                           tlast_o;

    match_core #(
        .ROW_SIZE       (   ROW_SIZE    ),
        .WIN_SIZE       (   WIN_SIZE    ),
        .BEAT_SIZE      (   BEAT_SIZE   ),
        .DATA_WIDTH     (   DATA_WIDTH  ),
        .READ_LATENCY   (   READ_LATENCY),
        .MATCH_TH       (   MATCH_TH    )
    ) match_core_inst   (
        .clk                (   aclk        ),
        .rst_n              (   aresetn     ),

        .phase_buf_dout     (   phase_buf_dout [i]  ),
        .phase_buf_empty    (   phase_buf_empty[i]  ),
        .phase_buf_rd_en    (   phase_buf_rd_en[i]  ),

        .cache_addr         (   cache_addr[i]       ),
        .cache_data         (   cache_dout[i]       ),

        .vld_o              (   match_vld_o         ),
        .not_found          (   not_found           ),
        .y_sub_y1           (   y_sub_y1            ), 
        .y_sub_y0           (   y_sub_y0            ), 
        .x0                 (   x0                  ), 
        .abs_phase1_pos_o   (   abs_phase1_pos_o    ),
        .tlast_o            (   tlast_o             )
    );

    logic                            dis_vld_o;
    logic signed [DATA_WIDTH-1:0]    disparity;
    logic                            dis_tlast_o;

    cal_disparity #(
        .DATA_WIDTH (   DATA_WIDTH  )
    ) cal_disparity_inst (
        .clk            (   aclk        ),
        .rst_n          (   aresetn     ),
        .vld_i          (   match_vld_o ),
        .tlast_i        (   tlast_o     ),
        .not_found      (   not_found   ),
        .x0             (   x0                  ),
        .y_sub_y0       (   y_sub_y0            ),
        .y_sub_y1       (   y_sub_y1            ),
        .abs_phase1_pos (   abs_phase1_pos_o    ),

        .vld_o          (   dis_vld_o           ),
        .disparity      (   disparity           ),
        .tlast_o        (   dis_tlast_o         )
    );

    sync_fifo #(
        .FIFO_DEPTH         (  BUFFER_DEPTH     ),
        .PROG_FULL_THRESH   (  BUFFER_DEPTH-10  ),
        .DATA_WIDTH         (  DATA_WIDTH+1     ),
        .READ_MODE          (  "fwft"           ),
        .READ_LATENCY       (   0               )
    ) disparity_fifo (
        .clk    (   aclk    ),
        .rst_n  (   aresetn ),

        .wr_en  (   dis_buf_wr_en[i]  ),
        .rd_en  (   dis_buf_rd_en[i]  ),
        .din    (   dis_buf_din[i]    ),
        .dout   (   dis_buf_dout[i]   ),

        .empty  (   dis_buf_empty[i]  ),
        .pfull  (   dis_buf_pfull[i]  )
    );
    assign dis_buf_wr_en[i] = dis_vld_o;
    assign dis_buf_din[i] = {dis_tlast_o, disparity};
end
endgenerate

//1280x1080
phase_cache #(
    .ROW_SIZE       (   ROW_SIZE        ),
    .WIN_SIZE       (   WIN_SIZE        ),
    .BEAT_SIZE      (   BEAT_SIZE       ),
    .DATA_WIDTH     (   DATA_WIDTH      ),
    .READ_LATENCY   (   READ_LATENCY    )
)phase_cache_inst(
    .aclk           (   aclk    ),
    .aresetn        (   aresetn ),

    .s_axis_tdata   (   cache_axis_tdata    ),
    .s_axis_tvalid  (   cache_axis_tvalid   ),
    .s_axis_tready  (   cache_axis_tready   ),
    .s_axis_tlast   (   cache_axis_tlast    ),

    .cache_addr     (   cache_addr          ),
    .cache_dout     (   cache_dout          )
);

endmodule
