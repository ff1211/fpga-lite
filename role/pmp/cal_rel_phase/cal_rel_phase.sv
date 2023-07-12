`timescale 1ns / 1ps
//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// cal_rel_phase.sv
// 
// Description:
// Calculate relative phase.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.12.04  ff          Initial version
// 1.1      2023.06.13  ff          Fix bugs and add the support of mod-rate filter 
//****************************************************************

module cal_rel_phase #(
    parameter PIPE_NUM = 8,
    parameter BTH = 10,
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

// Local parameters definition.
localparam DATA_WIDTH = 16;
localparam AXIS_DWIDTH = PIPE_NUM*DATA_WIDTH;
localparam PIXEL_PART_WIDTH = PIPE_NUM*8;
localparam PART_NUM = DATA_WIDTH/8;

logic [3:0]                             pixel_buf_wr_en;
logic [3:0]                             pixel_buf_rd_en;
logic [AXIS_DWIDTH:0]                   pixel_buf_din;
logic [3:0]                             pixel_buf_empty;
logic [3:0]                             pixel_buf_pfull;
logic [3:0][AXIS_DWIDTH:0]              pixel_buf_dout;
logic                                   init_win;

logic [PIPE_NUM-1:0][7:0]               pixel1;
logic [PIPE_NUM-1:0][7:0]               pixel2;
logic [PIPE_NUM-1:0][7:0]               pixel3;
logic [PIPE_NUM-1:0][7:0]               pixel4;

logic [DATA_WIDTH-1:0]                  buf_rd_cnt;
logic                                   cal_vld_i;
logic [PIPE_NUM-1:0]                    cal_vld;
logic [PIPE_NUM-1:0][DATA_WIDTH-1:0]    phase;
logic [PIPE_NUM-1:0]                    last;
logic [3:0]                             buf_switch;
logic                                   cal_last_i;

logic                                   phase_buf_wr_en;
logic                                   phase_buf_rd_en;
logic [AXIS_DWIDTH:0]                   phase_buf_din;
logic                                   phase_buf_pfull;
logic                                   phase_buf_empty;
logic [AXIS_DWIDTH:0]                   phase_buf_dout;

genvar i;
generate;
for (i = 0; i < 4; ++i) begin
    sync_fifo #(
        .FIFO_DEPTH         (  BUFFER_DEPTH/2       ),
        .PROG_FULL_THRESH   (  BUFFER_DEPTH/2-10    ),
        .DATA_WIDTH         (  AXIS_DWIDTH+1        ),
        .READ_MODE          (  "fwft"               ),
        .READ_LATENCY       (   0                   )
    ) pixel_fifo (
        .clk    (   aclk    ),
        .rst_n  (   aresetn ),
    
        .wr_en  (   pixel_buf_wr_en[i]  ),
        .rd_en  (   pixel_buf_rd_en[i]  ),
        .din    (   pixel_buf_din       ),
        .dout   (   pixel_buf_dout[i]   ),

        .empty  (   pixel_buf_empty[i]  ),
        .pfull  (   pixel_buf_pfull[i]  )
    );
    assign pixel_buf_rd_en[i] = cal_vld_i & init_win;
    assign pixel_buf_din = {s_axis_tlast, s_axis_tdata};
end
endgenerate

always @(posedge aclk) begin
    if(~aresetn)
        buf_rd_cnt <= 0;
    else if(init_win)
        buf_rd_cnt <= 0;
    else if(cal_vld_i)
        buf_rd_cnt <= buf_rd_cnt + 1;
    else
        buf_rd_cnt <= buf_rd_cnt;
end

assign init_win = (buf_rd_cnt == DATA_WIDTH/8-1);

// Schedule pixel buffer.
always @(posedge aclk) begin
    if(~aresetn)
        buf_switch <= 4'b0001;
    else begin
        if(s_axis_tvalid & s_axis_tready & s_axis_tlast)
            buf_switch <= {buf_switch[2:0], buf_switch[3]};
    end
end

// Set axis slave signal.
always@(*) begin
    case (buf_switch)
        4'b0001: s_axis_tready = ~pixel_buf_pfull[0];
        4'b0010: s_axis_tready = ~pixel_buf_pfull[1];
        4'b0100: s_axis_tready = ~pixel_buf_pfull[2];
        4'b1000: s_axis_tready = ~pixel_buf_pfull[3];
        default: s_axis_tready = 1'b0;
    endcase
    for (int i = 0; i < 4; ++i)
        pixel_buf_wr_en[i] = buf_switch[i] & s_axis_tvalid & s_axis_tready;
end

assign cal_vld_i = !pixel_buf_empty & ~phase_buf_pfull;
assign cal_last_i = pixel_buf_dout[0][AXIS_DWIDTH] & init_win;

genvar j;
generate;
for (j = 0; j < PIPE_NUM; j++) begin
// Phase and modulate rate calculation.
    logic [DATA_WIDTH-1:0] phase_o;
    rel_phase_4steps #(
        .BTH        (   BTH             ),
        .NOISE_CODE (   NOISE_CODE      )
    ) rel_phase_4steps_inst (
        .clk        (   aclk            ),
        .rst_n      (   aresetn         ),
        .vld_i      (   cal_vld_i       ),
        .pixel1_i   (   pixel1[j]       ),
        .pixel2_i   (   pixel2[j]       ),
        .pixel3_i   (   pixel3[j]       ),
        .pixel4_i   (   pixel4[j]       ),
        .last_i     (   cal_last_i      ),
        .vld_o      (   cal_vld[j]      ),
        .last_o     (   last[j]         ),
        .phase_o    (   phase_o         )
    );
    assign phase[j] = phase_o;
end
endgenerate
// Select input pixels.
always @(*) begin
    pixel1 = pixel_buf_dout[0][0+:PIXEL_PART_WIDTH];
    pixel2 = pixel_buf_dout[1][0+:PIXEL_PART_WIDTH];
    pixel3 = pixel_buf_dout[2][0+:PIXEL_PART_WIDTH];
    pixel4 = pixel_buf_dout[3][0+:PIXEL_PART_WIDTH];
    for (int i = 0; i < PART_NUM; i++) begin
        if(buf_rd_cnt == i) begin
            pixel1 = pixel_buf_dout[0][i*PIXEL_PART_WIDTH+:PIXEL_PART_WIDTH];
            pixel2 = pixel_buf_dout[1][i*PIXEL_PART_WIDTH+:PIXEL_PART_WIDTH];
            pixel3 = pixel_buf_dout[2][i*PIXEL_PART_WIDTH+:PIXEL_PART_WIDTH];
            pixel4 = pixel_buf_dout[3][i*PIXEL_PART_WIDTH+:PIXEL_PART_WIDTH];
        end
    end
end

// Phase buffer
sync_fifo #(
    .FIFO_DEPTH         (  BUFFER_DEPTH     ),
    .PROG_FULL_THRESH   (  BUFFER_DEPTH-30  ),
    .DATA_WIDTH         (  AXIS_DWIDTH+1     ),
    .READ_MODE          (  "fwft"           ),
    .READ_LATENCY       (   0               )
) phase_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   phase_buf_wr_en ),
    .rd_en  (   phase_buf_rd_en ),
    .din    (   phase_buf_din   ),
    .dout   (   phase_buf_dout  ),
    .pfull  (   phase_buf_pfull ),
    .empty  (   phase_buf_empty )
);
assign phase_buf_wr_en = cal_vld[0];
assign phase_buf_din = {last[0], phase};
assign phase_buf_rd_en = m_axis_tready & m_axis_tvalid;
assign m_axis_tdata = phase_buf_dout[AXIS_DWIDTH-1:0];
assign m_axis_tvalid = ~phase_buf_empty;
assign m_axis_tlast = phase_buf_dout[AXIS_DWIDTH];

endmodule
