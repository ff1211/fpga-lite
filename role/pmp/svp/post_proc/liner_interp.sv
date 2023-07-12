
//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// liner_interp.sv
// 
// Description:
// Core that do liner interpolation.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2023.03.22  ff          Initial version
//****************************************************************

`timescale 1ns/1ps

module liner_interp #(
    parameter DATA_WIDTH    = 16,
    parameter FORMAT        = 8,
    parameter USER_WIDTH    = 1,
    parameter ERROR_CODE    = 16'b1000_0000_0000_0000
) (
    input                                   clk,
    input                                   rst_n,
    input signed [DATA_WIDTH-1:0]           x_sub_x0,
    input signed [DATA_WIDTH-1:0]           x_sub_x1,
    input signed [DATA_WIDTH-1:0]           y1_sub_y0,
    input signed [DATA_WIDTH-1:0]           y0,
    input        [USER_WIDTH-1:0]           user_i,
    input                                   vld_i,

    output logic [USER_WIDTH-1:0]           user_o,
    output logic                            vld_o,
    output logic signed [DATA_WIDTH-1:0]    y
);

logic signed [DATA_WIDTH-1:0]           x_sub_x0_r0;
logic signed [DATA_WIDTH-1:0]           x_sub_x1_r;
logic signed [DATA_WIDTH-1:0]           y1_sub_y0_r0;
logic signed [DATA_WIDTH+FORMAT-1:0]    y1_sub_y0_r1;
logic signed [DATA_WIDTH-1:0]           y0_r0;
logic   [1:0][USER_WIDTH-1:0]           user_i_r;
logic   [1:0]                           vld_i_r;
logic signed [DATA_WIDTH-1:0]           slope;
logic                                   slope_vld;
logic        [USER_WIDTH-1:0]           slope_user;
logic signed [DATA_WIDTH-1:0]           x1_sub_x0;
logic signed [DATA_WIDTH-1:0]           y0_r1;
logic signed [DATA_WIDTH-1:0]           y0_r2;
logic signed [DATA_WIDTH-1:0]           x_sub_x0_r1;
logic signed [DATA_WIDTH-1:0]           x_sub_x0_r2;

// Reg input.
always @(posedge clk) begin
    x_sub_x0_r0 <= x_sub_y0;
    x_sub_x1_r <= x_sub_x1;
    y1_sub_y0_r0 <= y1_sub_y0;
    y0_r0 <= y0;
    user_i_r[0] <= user_i;
    vld_i_r[0] <= vld_i;
end

always @(posedge clk) begin
    y1_sub_y0_r1 <= y1_sub_y0_r0 << (FORMAT-1);
    x1_sub_x0 <= x_sub_x1_r + x_sub_x0_r0;
    x_sub_x0_r1 <= x_sub_x0_r0;
    y0_r1 <= y0_r0;
    user_i_r[1] <= user_i_r[0];
    vld_i_r[1] <= vld_i_r[0];
end

div_gen_0 div_inst (
    .aclk                   (   clk                 ),              // input wire aclk
    .s_axis_divisor_tvalid  (   vld_i_r[1]          ),              // input wire s_axis_divisor_tvalid
    .s_axis_divisor_tdata   (   x1_sub_x0           ),              // input wire [15 : 0] s_axis_divisor_tdata
    .s_axis_dividend_tvalid (   vld_i_r[1]          ),              // input wire s_axis_dividend_tvalid
    .s_axis_dividend_tuser  (   {y0_r1, x_sub_x0_r1}),              // input wire [16 : 0] s_axis_dividend_tuser
    .s_axis_dividend_tdata  (   y1_sub_y0_r1        ),              // input wire [23 : 0] s_axis_dividend_tdata
    .m_axis_dout_tvalid     (   slope_vld           ),              // output wire m_axis_dout_tvalid
    .m_axis_dout_tuser      (   slope_user          ),              // output wire [16 : 0] m_axis_dout_tuser
    .m_axis_dout_tdata      (   slope               )               // output wire [39 : 0] m_axis_dout_tdata
);

assign x_sub_x0_r2 = slope_user[0+:DATA_WIDTH];
assign y0_r2 = slope_user[DATA_WIDTH+:DATA_WIDTH];

always @(posedge clk) begin
    y <= y0_r2 + slope * x_sub_x0_r2;
    user_o <= slope_user;
    vld_o <= slope_vld;
end

endmodule