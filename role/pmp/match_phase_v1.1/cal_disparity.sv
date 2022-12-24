//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// cal_disparity.sv
// 
// Description:
// calculate disparity.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.12.22  ff          Initial version
//****************************************************************

`timescale 1ns/1ps

module cal_disparity #(
    parameter DATA_WIDTH = 16
) (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            vld_i,
    input  logic                            tlast_i,
    input  logic                            not_found,
    input  logic signed [DATA_WIDTH-1:0]    x0,
    input  logic signed [DATA_WIDTH-1:0]    y_sub_y0,
    input  logic signed [DATA_WIDTH-1:0]    y_sub_y1,
    input  logic signed [DATA_WIDTH-1:0]    abs_phase1_pos,

    output logic                            vld_o,
    output logic signed [DATA_WIDTH-1:0]    disparity,
    output logic                            tlast_o
);

logic signed [DATA_WIDTH-1:0]       x0_r;
logic signed [DATA_WIDTH-1:0]       y_sub_y0_r;
logic signed [DATA_WIDTH-1:0]       y_sub_y1_r;
logic signed [DATA_WIDTH-1:0]       abs_phase1_pos_r;
logic        [3:0]                  tlast_i_r;
logic        [3:0]                  vld_i_r;
logic        [1:0]                  not_found_r;
logic signed [23:0]                 a;
logic signed [DATA_WIDTH-1:0]       a_plus_b;
logic signed [DATA_WIDTH-1:0]       delta_x;
logic                               div_tlast;
logic                               div_vld;
logic        [DATA_WIDTH:0]         div_tuser;
logic [39:0]                        div_tdata;
logic signed [DATA_WIDTH-1:0]       disparity_p0;
logic signed [DATA_WIDTH-1:0]       disparity_p1;

// Reg input.
always @(posedge clk) begin
    x0_r <= x0 << 7;
    y_sub_y0_r <= y_sub_y0;
    y_sub_y1_r <= y_sub_y1;
    abs_phase1_pos_r <= abs_phase1_pos << 7;
    not_found_r[0] <= not_found;
end
always @(posedge clk) begin
    if(~rst_n) begin
        tlast_i_r[0] <= 0;
        vld_i_r[0] <= 0;
    end else begin
        tlast_i_r[0] <= tlast_i;
        vld_i_r[0] <= vld_i;
    end
end

// abs(y-y0) = a
// abs(y-y1) = b
// deltaX = a / (a + b)
// disparity = x0 - abs_phase1_pos + deltaX
always @(posedge clk) begin
    a <= y_sub_y0_r * 128;
    a_plus_b <= y_sub_y0_r - y_sub_y1_r;
    disparity_p0 <= x0_r - abs_phase1_pos_r;
    not_found_r [1] <= not_found_r[0];
end
always @(posedge clk) begin
    if(~rst_n) begin
        tlast_i_r   [1] <= 0;
        vld_i_r     [1] <= 0;
    end else begin
        tlast_i_r   [1] <= tlast_i_r[0];
        vld_i_r     [1] <= vld_i_r  [0];
    end
end

div_gen_0 div_inst (
    .aclk                   (   clk             ),  // input wire aclk
    .s_axis_divisor_tvalid  (   vld_i_r[1]      ),  // input wire s_axis_divisor_tvalid
    .s_axis_divisor_tdata   (   a_plus_b        ),  // input wire [15 : 0] s_axis_divisor_tdata
    .s_axis_dividend_tvalid (   vld_i_r[1]      ),  // input wire s_axis_dividend_tvalid
    .s_axis_dividend_tlast  (   tlast_i_r[1]    ),  // input wire s_axis_dividend_tlast
    .s_axis_dividend_tuser  (   {not_found_r[1],disparity_p0}),    // input wire [16 : 0] s_axis_dividend_tuser
    .s_axis_dividend_tdata  (   a               ),  // input wire [23 : 0] s_axis_dividend_tdata
    .m_axis_dout_tvalid     (   div_vld         ),  // output wire m_axis_dout_tvalid
    .m_axis_dout_tlast      (   div_tlast       ),  // output wire m_axis_dout_tlast
    .m_axis_dout_tuser      (   div_tuser       ),            // output wire [16 : 0] m_axis_dout_tuser
    .m_axis_dout_tdata      (   div_tdata       )   // output wire [39 : 0] m_axis_dout_tdata
);
assign delta_x = div_tdata[31:16];
assign disparity_p1 = div_tuser[DATA_WIDTH-1:0];

always @(posedge clk) begin
    disparity <= div_tuser[DATA_WIDTH]? 0 : disparity_p1 + delta_x;
end
always @(posedge clk) begin
    if(~rst_n) begin
        tlast_i_r   [2] <= 0;
        vld_i_r     [2] <= 0;
    end else begin
        tlast_i_r   [2] <= div_tlast;
        vld_i_r     [2] <= div_vld;
    end
end
assign vld_o = vld_i_r[2];
assign tlast_o = tlast_i_r[2];

endmodule