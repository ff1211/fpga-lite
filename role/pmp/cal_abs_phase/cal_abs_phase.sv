`timescale 1ns / 1ps
//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// cal_abs_phase.sv
// 
// Description:
// Calculate absolute phase.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.14  ff          Initial version
//****************************************************************

module cal_abs_phase #(
    parameter PIPE_NUM = 8,
    parameter RATIO_3TO2 = 8,
    parameter RATIO_2TO1 = 8,
    parameter NOISE_CODE = 16'b10100000_00000000,
    parameter BUFFER_DEPTH = 512
)(
    input aclk,
    input aresetn,

    input  logic [PIPE_NUM*16-1:0]  s_axis_tdata,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,
    input  logic                    s_axis_tlast,
    
    output logic [PIPE_NUM*16-1:0]  m_axis_tdata,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,
    output logic                    m_axis_tlast
);

logic [2:0]                 phase_buf_wr_en;
logic [2:0]                 phase_buf_rd_en;
logic [PIPE_NUM*16:0]       phase_buf_din;
logic [2:0]                 phase_buf_empty;
logic [2:0]                 phase_buf_pfull;
logic [2:0][PIPE_NUM*16:0]  phase_buf_dout;

logic                       cal_vld_i;
logic [PIPE_NUM-1:0]        cal_vld;
logic [PIPE_NUM-1:0][15:0]  abs_phase;
logic [PIPE_NUM-1:0]        last;
logic [2:0]                 buf_switch;

logic                       abs_phase_buf_wr_en;
logic                       abs_phase_buf_rd_en;
logic [PIPE_NUM*16:0]       abs_phase_buf_din;
logic                       abs_phase_buf_pfull;
logic                       abs_phase_buf_empty;
logic [PIPE_NUM*16:0]       abs_phase_buf_dout;

genvar i;
generate;
for (i = 0; i < 3; ++i) begin
    sync_fifo #(
        .FIFO_DEPTH         (  BUFFER_DEPTH     ),
        .PROG_FULL_THRESH   (  BUFFER_DEPTH-10  ),
        .DATA_WIDTH         (  PIPE_NUM*16+1    ),
        .READ_MODE          (  "fwft"           ),
        .READ_LATENCY       (   0               )
    ) phase_fifo (
        .clk    (   aclk    ),
        .rst_n  (   aresetn ),
    
        .wr_en  (   phase_buf_wr_en[i]  ),
        .rd_en  (   phase_buf_rd_en[i]  ),
        .din    (   phase_buf_din       ),
        .dout   (   phase_buf_dout[i]   ),

        .empty  (   phase_buf_empty[i]  ),
        .pfull  (   phase_buf_pfull[i]  )
    );
    assign phase_buf_rd_en[i] = cal_vld_i;
    assign phase_buf_din = {s_axis_tlast, s_axis_tdata};
end
endgenerate

// Schedule pixel buffer.
always @(posedge aclk) begin
    if(~aresetn)
        buf_switch <= 3'b001;
    else begin
        if(s_axis_tvalid & s_axis_tready & s_axis_tlast)
            buf_switch <= {buf_switch[1:0], buf_switch[2]};
    end
end

// Set axis slave signal.
always@(*) begin
    case (buf_switch)
        3'b001: s_axis_tready = ~phase_buf_pfull[0];
        3'b010: s_axis_tready = ~phase_buf_pfull[1];
        3'b100: s_axis_tready = ~phase_buf_pfull[2];
        default: s_axis_tready = 1'b0;
    endcase
    for (int i = 0; i < 3; ++i)
        phase_buf_wr_en[i] = buf_switch[i] & s_axis_tvalid & s_axis_tready;
end

assign cal_vld_i = ~phase_buf_empty[0] & ~phase_buf_empty[1] & ~phase_buf_empty[2] & ~phase_buf_pfull;

genvar j;
generate;
for (j = 0; j < PIPE_NUM; ++j) begin
// Phase and modulate rate calculation.
    logic [15:0] abs_phase_o;
    abs_phase_3steps #(
        .RATIO_3TO2 (   RATIO_3TO2  ),
        .RATIO_2TO1 (   RATIO_2TO1  ),
        .NOISE_CODE (   NOISE_CODE  )
    ) abs_phase_3steps_inst (
        .clk            (   aclk        ),
        .rst_n          (   aresetn     ),
        .vld_i          (   cal_vld_i   ),
        .phase1_i       (   phase_buf_dout[0][j*16+:16]),
        .phase2_i       (   phase_buf_dout[1][j*16+:16]),
        .phase3_i       (   phase_buf_dout[2][j*16+:16]),
        .last_i         (   phase_buf_dout[0][PIPE_NUM*16]),
        .vld_o          (   cal_vld[j]  ),
        .abs_phase_o    (   abs_phase_o ),
        .last_o         (   last[j]     )
    );

    assign abs_phase[j] = abs_phase_o;
end
endgenerate

// Absolute phase buffer
sync_fifo #(
    .FIFO_DEPTH         (  BUFFER_DEPTH     ),
    .PROG_FULL_THRESH   (  BUFFER_DEPTH-10  ),
    .DATA_WIDTH         (  PIPE_NUM*16+1    ),
    .READ_MODE          (  "fwft"           ),
    .READ_LATENCY       (   0               )
) abs_phase_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   abs_phase_buf_wr_en ),
    .rd_en  (   abs_phase_buf_rd_en ),
    .din    (   abs_phase_buf_din   ),
    .dout   (   abs_phase_buf_dout  ),
    .pfull  (   abs_phase_buf_pfull ),
    .empty  (   abs_phase_buf_empty )
);
assign abs_phase_buf_wr_en = cal_vld[0];
assign abs_phase_buf_rd_en = m_axis_tready & m_axis_tvalid;
assign abs_phase_buf_din = {last[0], abs_phase};
assign m_axis_tdata = abs_phase_buf_dout[PIPE_NUM*16-1:0];
assign m_axis_tvalid = ~abs_phase_buf_empty;
assign m_axis_tlast = abs_phase_buf_dout[PIPE_NUM*16];

endmodule
