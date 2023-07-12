//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// control.sv
// 
// Description:
// Control core of the phase matching core.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2023.03.16  ff          Initial version
//****************************************************************

`timescale 1ns / 1ps

module output_control #(
    parameter MAX_DIS = 128,
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16,
    parameter USER_WIDTH = 51,
    parameter ISSUE_WIDTH = 4
) (
    input  logic                                    aclk,
    input  logic                                    aresetn,

    output logic                                    dis_buf_rd_en,
    input  logic                                    dis_buf_empty,
    input  logic [ISSUE_WIDTH-1:0][USER_WIDTH-1:0]  dis_buf_dout,

    output logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]    m_axis_tdata,
    output logic                                    m_axis_tvalid,
    input  logic                                    m_axis_tready,
    output logic                                    m_axis_tlast
);

logic [DATA_WIDTH-1:0] rd_cnt;

always @(posedge aclk) begin
    if(~aresetn)
        rd_cnt <= 0;
    else if(rd_cnt == BEAT_SIZE / ISSUE_WIDTH - 1)
        rd_cnt <= 0;
    else if(dis_buf_rd_en)
        rd_cnt <= rd_cnt + 1;
    else
        rd_cnt <= rd_cnt;
end
assign dis_buf_rd_en = ~dis_buf_empty;

always @(posedge aclk) 
    m_axis_tvalid <= (rd_cnt == BEAT_SIZE / ISSUE_WIDTH - 1);

always @(posedge aclk) begin
    m_axis_tdata <= 0;
    for (int i = 0; i < BEAT_SIZE / ISSUE_WIDTH; i++)
        for (int j = 0; j < ISSUE_WIDTH; j++)
            m_axis_tdata[i*ISSUE_WIDTH+j] <= dis_buf_dout[j][2*DATA_WIDTH+:DATA_WIDTH];
end

assign m_axis_tlast = 1;

endmodule