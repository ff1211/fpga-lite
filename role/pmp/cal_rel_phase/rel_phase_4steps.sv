`timescale 1ns/1ps
//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// rel_phase_4steps.sv
// 
// Description:
// Calculate relative phase according to 4-step algorithm.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.12.04  ff          Initial version
//****************************************************************

module rel_phase_4steps #(
    parameter DATA_WIDTH = 16
) (
    input       clk,
    input       rst_n,
    input       vld_i,
    input [7:0] pixel1_i,
    input [7:0] pixel2_i,
    input [7:0] pixel3_i,
    input [7:0] pixel4_i,
    input       tlast_i,
    output                          vld_o,
    output signed [DATA_WIDTH-1:0]  phase_o,
    output                          tlast_o
);

logic signed [DATA_WIDTH-1:0]   pixel1_r;
logic signed [DATA_WIDTH-1:0]   pixel2_r;
logic signed [DATA_WIDTH-1:0]   pixel3_r;
logic signed [DATA_WIDTH-1:0]   pixel4_r;
logic signed [DATA_WIDTH-1:0]   diff_42;
logic signed [DATA_WIDTH-1:0]   diff_13;
logic signed [DATA_WIDTH-1:0]   diff_42_norm;
logic signed [DATA_WIDTH-1:0]   diff_13_norm;
logic signed [DATA_WIDTH-1:0]   diff_42_norm_s;
logic signed [DATA_WIDTH-1:0]   diff_13_norm_s;
logic        [3:0]              vld_i_r;
logic        [3:0]              tlast_i_r;

// Buffer pixel data and shift.
// Fixed-point twos complement numbers with an integer width of 8 bits (7QN format).
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[0] <= 0;
        tlast_i_r[0] <= 0;
    end else begin
        pixel1_r <= pixel1_i;
        pixel2_r <= pixel2_i;
        pixel3_r <= pixel3_i;
        pixel4_r <= pixel4_i;
        vld_i_r[0] <= vld_i;
        tlast_i_r[0] <= tlast_i;
    end
end

// Substract.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[1] <= 0;
        tlast_i_r[1] <= 0;
    end else begin
        diff_42 <= pixel4_r - pixel2_r;
        diff_13 <= pixel1_r - pixel3_r;
        vld_i_r[1] <= vld_i_r[0];
        tlast_i_r[1] <= tlast_i_r[0];
    end
end

// Scale diff to get higher accuracy.
// Power 2.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[2] <= 0;
        tlast_i_r[2] <= 0;
    end else begin
        diff_42_norm <= diff_42 * 64;
        diff_13_norm <= diff_13 * 64;
        vld_i_r[2] <= vld_i_r[1];
        tlast_i_r[2] <= tlast_i_r[1];
    end
end

// Shift.
// Add.
// Fixed-point twos complement numbers with an integer width of 2 bits (1QN format).
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[3] <= 0;
        tlast_i_r[3] <= 0;
    end else begin
        diff_42_norm_s <= diff_42_norm;
        diff_13_norm_s <= diff_13_norm;
        vld_i_r[3] <= vld_i_r[2];
        tlast_i_r[3] <= tlast_i_r[2];
    end
end

// Arc Tan.
// Delay is 20 cycles.
cordic_arctan cordic_arctan_inst (
    .aclk                       (   clk         ),
    .aresetn                    (   rst_n       ),
    .s_axis_cartesian_tvalid    (   vld_i_r[3]  ),
    .s_axis_cartesian_tlast     (   tlast_i_r[3]),
    .s_axis_cartesian_tdata     (   {diff_42_norm_s, diff_13_norm_s} ),
    .m_axis_dout_tvalid         (   vld_o       ),
    .m_axis_dout_tlast          (   tlast_o     ),
    .m_axis_dout_tdata          (   phase_o     )
);

endmodule