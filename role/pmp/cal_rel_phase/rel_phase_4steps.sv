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

module rel_phase_4steps # (
    parameter BTH = 10,
    parameter NOISE_CODE = 16'b10100000_00000000
)(
    input                       clk,
    input                       rst_n,
    input                       vld_i,
    input [7:0]                 pixel1_i,
    input [7:0]                 pixel2_i,
    input [7:0]                 pixel3_i,
    input [7:0]                 pixel4_i,
    input                       last_i,
    output logic                vld_o,
    output logic signed [15:0]  phase_o,
    output logic                last_o
);

// phase_o is 16-bit fixed-point twos complement number with an integer width of 2 bits (1QN format).
logic        [3:0]  vld_i_r;
logic        [3:0]  last_i_r;
logic signed [15:0] pixel1_r;
logic signed [15:0] pixel2_r;
logic signed [15:0] pixel3_r;
logic signed [15:0] pixel4_r;
logic signed [16:0] diff_42;
logic signed [16:0] diff_13;
logic        [15:0] square_42;
logic        [15:0] square_13;
logic        [16:0] square_sum;
logic signed [16:0] diff_42_norm;
logic signed [16:0] diff_13_norm;
logic signed [16:0] diff_42_norm_r;
logic signed [16:0] diff_13_norm_r;
logic               sqsum_buf_wr_en;
logic               sqsum_buf_rd_en;
logic        [16:0] sqsum_buf_din;
logic        [16:0] sqsum_buf_dout;

logic signed [16:0] arctan;
logic               arctan_vld;
logic               arctan_tlast;

// Buffer pixel data and shift.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[0] <= 0;
        last_i_r[0] <= 0;
    end else begin
        pixel1_r <= pixel1_i;
        pixel2_r <= pixel2_i;
        pixel3_r <= pixel3_i;
        pixel4_r <= pixel4_i;
        vld_i_r[0] <= vld_i;
        last_i_r[0] <= last_i;
    end
end

// Substract.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[1] <= 0;
        last_i_r[1] <= 0;
    end else begin
        diff_42 <= pixel4_r - pixel2_r;
        diff_13 <= pixel1_r - pixel3_r;
        vld_i_r[1] <= vld_i_r[0];
        last_i_r[1] <= last_i_r[0];
    end
end

// Scale diff to get higher accuracy.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[2] <= 0;
        last_i_r[2] <= 0;
    end else begin
        square_42 <= diff_42 * diff_42;
        square_13 <= diff_13 * diff_13;
        diff_42_norm <= diff_42 * 128;
        diff_13_norm <= diff_13 * 128;
        vld_i_r[2] <= vld_i_r[1];
        last_i_r[2] <= last_i_r[1];
    end
end

// Scale the square sum to get better mod rate calculation accuracy.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[3] <= 0;
        last_i_r[3] <= 0;
    end else begin
        square_sum <= square_42 + square_13;
        diff_42_norm_r <= diff_42_norm;
        diff_13_norm_r <= diff_13_norm;
        vld_i_r[3] <= vld_i_r[2];
        last_i_r[3] <= last_i_r[2];
    end
end

// Arc Tan.
// 21 cycles' delay
// Input fixed-point twos complement numbers with an integer width of 2 bits (1QN format).
// Output fixed-point twos complement number with an integer width of 3 bits (2QN format).
cordic_arctan cordic_arctan_inst (
    .aclk                       (   clk         ),
    .aresetn                    (   rst_n       ),
    .s_axis_cartesian_tvalid    (   vld_i_r[3]  ),
    .s_axis_cartesian_tlast     (   last_i_r[3]),
    .s_axis_cartesian_tdata     (   {{7'b0,diff_42_norm_r}, {7'b0,diff_13_norm_r}} ),
    .m_axis_dout_tvalid         (   arctan_vld  ),
    .m_axis_dout_tlast          (   arctan_tlast),
    .m_axis_dout_tdata          (   arctan      )
);

// Match delay of Square Root and Arctan
sync_fifo #(
    .FIFO_DEPTH         (  32       ),
    .PROG_FULL_THRESH   (  24       ),
    .DATA_WIDTH         (  17       ),
    .READ_MODE          (  "fwft"   ),
    .READ_LATENCY       (   0       )
) square_root_fifo (
    .clk    (   clk     ),
    .rst_n  (   rst_n   ),

    .wr_en  (   sqsum_buf_wr_en ),
    .rd_en  (   sqsum_buf_rd_en ),
    .din    (   sqsum_buf_din   ),
    .dout   (   sqsum_buf_dout  )
);
assign sqsum_buf_wr_en = vld_i_r[3];
assign sqsum_buf_rd_en = arctan_vld;
assign sqsum_buf_din = square_sum;

always @(posedge clk) begin
    if(arctan_vld)
        phase_o <= (sqsum_buf_dout > (BTH * BTH * 4))? arctan : NOISE_CODE;
    else
        phase_o <= 'b0;
    vld_o <= arctan_vld;
    last_o <= arctan_tlast;
end

endmodule