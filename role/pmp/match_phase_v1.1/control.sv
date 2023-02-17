//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// control.sv
// 
// Description:
// Schedule phases and send them to match tree and get result.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.22  ff          Initial version
//****************************************************************

`timescale 1ns/1ps

module control #(
    parameter ROW_SIZE = 1280,
    parameter WIN_SIZE = 128,
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16,
    parameter BUFFER_DEPTH = 512
) (
    input  logic                                    clk,
    input  logic                                    rst_n,

    input  logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]    s_axis_tdata,
    input  logic                                    s_axis_tvalid,
    output logic                                    s_axis_tready,
    input  logic                                    s_axis_tlast,

    output logic [BEAT_SIZE*DATA_WIDTH-1:0]         m_cache_axis_tdata,
    output logic                                    m_cache_axis_tvalid,
    input  logic                                    m_cache_axis_tready,
    output logic                                    m_cache_axis_tlast,

    output logic                                    phase_buf_wr_en,
    output logic [BEAT_SIZE-1:0][DATA_WIDTH*2:0]    phase_buf_din,
    input  logic [BEAT_SIZE-1:0]                    phase_buf_pfull,

    output logic [BEAT_SIZE-1:0]                    dis_buf_rd_en,
    input  logic [BEAT_SIZE-1:0]                    dis_buf_empty,
    input  logic [BEAT_SIZE-1:0][DATA_WIDTH:0]      dis_buf_dout,

    output logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]    m_axis_tdata,
    output logic                                    m_axis_tvalid,
    input  logic                                    m_axis_tready,
    output logic                                    m_axis_tlast
);

logic [1:0]                             axis_switch;
logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   disparity_r;
logic [BEAT_SIZE-1:0]                   disparity_vld;
logic [BEAT_SIZE*DATA_WIDTH:0]          phase_beat_r;
logic [$clog2(ROW_SIZE/BEAT_SIZE)-1:0]  phase_beats_shift;
logic [DATA_WIDTH-1:0]                  abs_phase_pos_cnt;
logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   abs_phase_pos;
logic [1:0]                             packet_cnt;
logic                                   ready_for_receive;

// Axis switch. Load phase2 to cache and load phase1 to fifo.
always @(posedge clk) begin
    if(~rst_n)
        axis_switch <= 2'b01;
    else begin
        if(s_axis_tvalid & s_axis_tready & s_axis_tlast)
            axis_switch <= {axis_switch[0], axis_switch[1]};
    end
end

// Count input packet.
always @(posedge clk) begin
    if(~rst_n)
        packet_cnt <= 0;
    else if((packet_cnt == 2) & (m_axis_tlast & m_axis_tvalid & m_axis_tready))
        packet_cnt <= 0;
    else if(s_axis_tvalid & s_axis_tready & s_axis_tlast)
        packet_cnt <= packet_cnt + 1;
    else
        packet_cnt <= packet_cnt;
end
assign ready_for_receive = (packet_cnt != 2);

assign m_cache_axis_tdata   = s_axis_tdata;
assign m_cache_axis_tvalid  = axis_switch[0]? s_axis_tvalid : 0;
assign m_cache_axis_tlast   = s_axis_tlast;

assign s_axis_tready        = axis_switch[0]? m_cache_axis_tready & ready_for_receive : ~phase_buf_pfull[0] & rst_n & ready_for_receive;

assign phase_buf_wr_en      = axis_switch[0]? 0 : s_axis_tvalid & s_axis_tready;

// Calculate position.
always @(posedge clk) begin
    if(~rst_n)
        abs_phase_pos_cnt <= 0;
    else if(s_axis_tvalid & s_axis_tready & s_axis_tlast)
        abs_phase_pos_cnt <= 0;
    else if(s_axis_tvalid & s_axis_tready)
        abs_phase_pos_cnt <= abs_phase_pos_cnt + BEAT_SIZE;
    else
        abs_phase_pos_cnt <= 0;
end
always @(*) begin
    for (int i = 0; i < BEAT_SIZE; i++) begin
        abs_phase_pos[i] = abs_phase_pos_cnt + i;
        phase_buf_din[i] = {s_axis_tlast, abs_phase_pos[i], s_axis_tdata[i]};
    end
end

// Send disparity to axi stream.
always @(*) begin
    m_axis_tvalid = !dis_buf_empty;
    dis_buf_rd_en = (m_axis_tvalid & m_axis_tready)? {BEAT_SIZE{1'b1}} : 'b0;
    for (int i = 0; i < BEAT_SIZE; i++)
        m_axis_tdata[i] = dis_buf_dout[i][DATA_WIDTH-1:0];
    m_axis_tlast = dis_buf_dout[0][DATA_WIDTH];
end

endmodule