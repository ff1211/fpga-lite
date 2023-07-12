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

module input_control #(
    parameter MAX_DIS = 128,
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16
) (
    input  logic                                    aclk,
    input  logic                                    aresetn,

    input  logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]    s_axis_tdata,
    input  logic                                    s_axis_tvalid,
    output logic                                    s_axis_tready,
    input  logic                                    s_axis_tlast,

    output logic                                    lp_buf_wr_en,
    output logic [MAX_DIS*DATA_WIDTH-1:0]           lp_buf_din,
    input  logic                                    lp_buf_pfull,

    output logic                                    rp_buf_wr_en,
    output logic [BEAT_SIZE*DATA_WIDTH:0]           rp_buf_din,
    input  logic                                    rp_buf_pfull
);

localparam LP_BEAT_NUM = MAX_DIS / BEAT_SIZE;
localparam BEAT_WIDTH = BEAT_SIZE * DATA_WIDTH;

logic [1:0]                     axis_switch;
logic [DATA_WIDTH-1:0]          beat_cnt;
logic                           write_zeros;

// Axis switch.
always @(posedge aclk) begin
    if(~aresetn)
        axis_switch <= 2'b01;
    else begin
        if(s_axis_tvalid & s_axis_tready & s_axis_tlast)
            axis_switch <= {axis_switch[0], axis_switch[1]};
    end
end

// First right then left.
always @(posedge aclk) begin
    if(~aresetn)
        beat_cnt <= 0;
    else if (beat_cnt == LP_BEAT_NUM - 1)
        beat_cnt <= 0;
    else if (s_axis_tvalid & s_axis_tready & axis_switch[1])
        beat_cnt <= beat_cnt + 1;
    else
        beat_cnt <= beat_cnt;
end
// Write a beat of data with content of 0 for convenience of later matching process.
always @(posedge aclk) begin
    if(write_zeros)
        lp_buf_din <= 0;
    else
        for (int i = 0; i < LP_BEAT_NUM; i++) begin
            if(i == beat_cnt)
                lp_buf_din[i*BEAT_WIDTH+:BEAT_WIDTH] <= s_axis_tdata;
        end
end
always @(posedge aclk) begin
    if(~aresetn)
        lp_buf_wr_en <= 0;
    else if((beat_cnt == LP_BEAT_NUM - 1) || write_zeros)
        lp_buf_wr_en <= 1;
    else
        lp_buf_wr_en <= 0;
end
always @(posedge aclk) begin
    if(~aresetn)
        write_zeros <= 0;
    else if (s_axis_tvalid & s_axis_tready & s_axis_tlast & axis_switch[1])
        write_zeros <= 1;
    else
        write_zeros <= 0;
end

assign rp_buf_wr_en     = s_axis_tvalid & s_axis_tready & axis_switch[0];
assign rp_buf_din       = {s_axis_tlast, s_axis_tdata};

assign s_axis_tready    = axis_switch[0]? ~rp_buf_pfull : ~lp_buf_pfull;

endmodule