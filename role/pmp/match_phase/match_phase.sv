`timescale 1ns / 1ps
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

module match_phase #(
    parameter ROW_SIZE = 1280,
    parameter WIN_SIZE = 64,
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

logic                                   phase_buf_wr_en;
logic                                   phase_buf_rd_en;
logic [BEAT_WIDTH:0]                    phase_buf_din;
logic                                   phase_buf_empty;
logic                                   phase_buf_pfull;
logic [BEAT_WIDTH:0]                    phase_buf_dout;

logic signed [DATA_WIDTH-1:0]           abs_phase1      [BEAT_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]           abs_phase1_pos  [BEAT_SIZE-1:0];
logic                                   vld_o;
logic signed [DATA_WIDTH-1:0]           disparity       [BEAT_SIZE-1:0];
logic [BEAT_SIZE-1:0]                   vld_i;

control #(
    .ROW_SIZE       (   ROW_SIZE        ),
    .WIN_SIZE       (   WIN_SIZE        ),
    .BEAT_SIZE      (   BEAT_SIZE       ),
    .DATA_WIDTH     (   DATA_WIDTH      ),
    .BUFFER_DEPTH   (   BUFFER_DEPTH    )
) control_inst(
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
    .phase_buf_rd_en    (   phase_buf_rd_en     ),
    .phase_buf_din      (   phase_buf_din       ),
    .phase_buf_empty    (   phase_buf_empty     ),
    .phase_buf_pfull    (   phase_buf_pfull     ),
    .phase_buf_dout     (   phase_buf_dout      ),

    .abs_phase1         (   abs_phase1          ),
    .abs_phase1_pos     (   abs_phase1_pos      ),
    .vld_o              (   vld_o               ),

    .disparity          (   disparity           ),
    .vld_i              (   vld_i               ),

    .m_axis_tdata       (   m_axis_tdata        ),
    .m_axis_tvalid      (   m_axis_tvalid       ),
    .m_axis_tready      (   m_axis_tready       ),
    .m_axis_tlast       (   m_axis_tlast        )
);

genvar i;
generate
for (i = 0; i < BEAT_SIZE; i++) begin
    match_core #(
        .ROW_SIZE       (   ROW_SIZE    ),
        .WIN_SIZE       (   WIN_SIZE    ),
        .BEAT_SIZE      (   BEAT_SIZE   ),
        .DATA_WIDTH     (   DATA_WIDTH  ),
        .READ_LATENCY   (   READ_LATENCY),
        .MATCH_TH       (   MATCH_TH    )
    ) match_core_inst (
        .clk            (   aclk                ),
        .rst_n          (   aresetn             ),
        .abs_phase1     (   abs_phase1[i]       ),
        .abs_phase1_pos (   abs_phase1_pos[i]   ),
        .vld_i          (   vld_o               ),
        .cache_addr     (   cache_addr[i]       ),
        .cache_data     (   cache_dout[i]       ),
        .disparity      (   disparity[i]        ),
        .vld_o          (   vld_i[i]            )
    );
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

sync_fifo #(
    .FIFO_DEPTH         (  BUFFER_DEPTH     ),
    .PROG_FULL_THRESH   (  BUFFER_DEPTH-10  ),
    .DATA_WIDTH         (  BEAT_WIDTH+1     ),
    .READ_MODE          (  "fwft"           ),
    .READ_LATENCY       (   0               )
) phase_1_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   phase_buf_wr_en     ),
    .rd_en  (   phase_buf_rd_en     ),
    .din    (   phase_buf_din       ),
    .dout   (   phase_buf_dout      ),

    .empty  (   phase_buf_empty     ),
    .pfull  (   phase_buf_pfull     )
);

endmodule
