`timescale 1ns / 1ps
//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// abs_phase_3steps.sv
// 
// Description:
// Calculate absolute phase based on 3-step heterodyne algorithm.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.14  ff          Initial version.
// 1.1      2022.11.28  ff          Fix bugs.
//****************************************************************

module abs_phase_3steps #(
    parameter RATIO_3TO2 = 8,
    parameter RATIO_2TO1 = 8,
    parameter NOISE_CODE = 16'b10100000_00000000
) (
    input                   clk,
    input                   rst_n,
    input                   vld_i,
    input signed [15:0]     phase1_i,
    input signed [15:0]     phase2_i,
    input signed [15:0]     phase3_i,
    input                   last_i,
    output                  vld_o,
    output signed [15:0]    abs_phase_o,
    output                  last_o
);

localparam POINT_5_8QN_24B          = 24'b00000000_01000000_00000000;
localparam POINT_5_5QN_24B          = 24'b00000010_00000000_00000000;
localparam TWO_8QN_24B              = 24'b00000001_00000000_00000000;
localparam TWO_5QN_24B              = 24'b00001000_00000000_00000000;

logic signed [23:0] phase1_r0;
logic signed [23:0] phase1_r1;
logic signed [23:0] phase1_r2;
logic signed [23:0] phase1_r3;
logic signed [23:0] phase1_r4;
logic signed [23:0] phase1_r5;
logic signed [23:0] phase1_r6;
logic signed [23:0] phase1_r7;
logic signed [23:0] phase1_r8;
logic signed [23:0] phase1_r9;
logic signed [23:0] phase1_r10;
logic signed [23:0] phase1_r11;
logic signed [23:0] phase1_r12;
logic signed [23:0] phase1_r13;
logic signed [23:0] phase1_r14;
logic signed [23:0] phase1_r15;
logic signed [23:0] phase2_r0;
logic signed [23:0] phase3_r0;

logic signed [23:0] phase1sub3;
logic signed [23:0] phase2sub3;
logic signed [23:0] phase13sub23;

logic signed [23:0] phase13;
logic signed [23:0] phase23;
logic signed [23:0] phase123;
logic signed [23:0] phase13_r0;
logic signed [23:0] phase13_r1;
logic signed [23:0] phase13_r2;
logic signed [23:0] phase13_r3;
logic signed [23:0] phase13_r4;
logic signed [23:0] phase13_r5;
logic signed [23:0] phase13_r6;

logic signed [23:0] abs_phase13_p0;
logic signed [23:0] abs_phase13_p1;
logic signed [23:0] abs_phase13_p2;
logic signed [23:0] abs_phase13_p3;
logic signed [23:0] abs_phase13_p4;
logic signed [23:0] abs_phase13;

logic signed [23:0] abs_phase1_p0;
logic signed [23:0] abs_phase1_p1;
logic signed [23:0] abs_phase1_p2;
logic signed [23:0] abs_phase1_p3;
logic signed [23:0] abs_phase1_p4;
logic signed [23:0] abs_phase1;

logic  [16:0]    noise_r;
logic  [16:0]    vld_i_r;
logic  [16:0]    last_i_r;

// Delay handshake signals.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r <= 0;
        last_i_r <= 0;
        noise_r <= 0;
    end else begin
        noise_r[0] <= (phase1_i == NOISE_CODE) || (phase2_i == NOISE_CODE) || (phase3_i == NOISE_CODE);
        vld_i_r[0] <= vld_i;
        last_i_r[0] <= last_i;
        for (int i = 0; i < 16; i++) begin
            vld_i_r[i+1] <= vld_i_r[i];
            last_i_r[i+1] <= last_i_r[i];
            noise_r[i+1] <= noise_r[i];
        end
    end
end

// 0 stage.
// Buffer pixel data and extent it to 24bits.
// Fixed-point twos complement numbers with an integer width of 9 bits (8QN format).
// Maximum 256pi.

// as absoulte phase13' range is less than 32 times phase13
// shift phase1, phase2 and phase3 to 24bit twos complement numbers with an integer width of 5 bits.
// For better calculation precision.
always @(posedge clk) begin
    phase1_r0 <= phase1_i * 16;
    phase2_r0 <= phase2_i * 16;
    phase3_r0 <= phase3_i * 16;
end

// 1 stage.
// Heterodyne 13 and 23
always @(posedge clk) begin
    phase1_r1 <= phase1_r0;
    phase1sub3 <= phase1_r0 - phase3_r0;
    phase2sub3 <= phase2_r0 - phase3_r0;
end

// 2 stage.
// Heterodyne 13 and 23
always @(posedge clk) begin
    phase1_r2 <= phase1_r1;
    phase13 <= phase1sub3[23]? (phase1sub3 + TWO_5QN_24B) : phase1sub3;
    phase23 <= phase2sub3[23]? (phase2sub3 + TWO_5QN_24B) : phase2sub3;
end

// 3 stage.
// Register phase13.
// Substract phase13 and phase23.
always @(posedge clk) begin
    phase1_r3 <= phase1_r2;
    phase13_r0 <= phase13;
    phase13sub23 <= phase13 - phase23;
end

// Register phase13_r0.
// Heterodyne 123
// 4 stage.
always @(posedge clk) begin
    phase1_r4 <= phase1_r3;
    phase13_r1 <= phase13_r0;
    phase123 <= phase13sub23[23]? (phase13sub23 + TWO_5QN_24B) : phase13sub23;
end

// absPhase13 = phase13 + PI_2 * round((phase123 * ratio_3to2 - phase13) / PI_2);
// absPhaseMap.at<TYPE>(i, j) = phase1 + PI_2 * round((absPhase13 * ratio_2to1 - phase1) / PI_2);

// 5 stage.
// Calculate phase123 * ratio_3to2
always @(posedge clk) begin
    phase1_r5 <= phase1_r4;
    phase13_r2 <= phase13_r1;
    abs_phase13_p0 <= phase123 * RATIO_3TO2;
end

// 6 stage.
// phase123 * ratio_3to2 - phase13
always @(posedge clk) begin
    phase1_r6 <= phase1_r5;
    phase13_r3 <= phase13_r2;
    abs_phase13_p1 <= abs_phase13_p0 - phase13_r2;
end

// 7 stage.
// (phase123 * ratio_3to2 - phase13) / PI_2
always @(posedge clk) begin
    phase1_r7 <= phase1_r6;
    phase13_r4 <= phase13_r3;
    abs_phase13_p2 <= abs_phase13_p1 >>> 1;
end

// 8 stage.
//(phase123 * ratio_3to2 - phase13) / PI_2 + 0.5
always @(posedge clk) begin
    phase1_r8 <= phase1_r7;
    phase13_r5 <= phase13_r4;
    abs_phase13_p3 <= round(abs_phase13_p2, 18);
end

// 9 stage.
// PI_2 * round((phase123 * ratio_3to2 - phase13) / PI_2)
always @(posedge clk) begin
    phase1_r9 <= phase1_r8;
    phase13_r6 <= phase13_r5;
    abs_phase13_p4 <= abs_phase13_p3 * 2;
end

// 10 stage.
// phase13 + PI_2 * round((phase123 * ratio_3to2 - phase13) / PI_2)
// shift abs_phase13 to 24bit twos complement numbers with an integer width of 8 bits.
// before shift, add 24'b100 for rounding off to get better precision.
// As it is larger than 0, using logic shift.
always @(posedge clk) begin
    phase1_r10 <= phase1_r9 >>> 3;
    // abs_phase13 <= abs_phase13_p4 + phase13_r6 >> 3;
    abs_phase13 <= round(abs_phase13_p4 + phase13_r6, 3) >> 3;
end

// 11 stage.
// phase1 + PI_2 * round((absPhase13 * ratio_2to1 - phase1) / PI_2);
// Calculate absPhase13 * ratio_2to1
always @(posedge clk) begin
    phase1_r11 <= phase1_r10;
    abs_phase1_p0 <= abs_phase13 * RATIO_2TO1;
end

// 12 stage.
// Calculate absPhase13 * ratio_2to1 - phase1
always @(posedge clk) begin
    phase1_r12 <= phase1_r11;
    abs_phase1_p1 <= abs_phase1_p0 - phase1_r11;
end

// 13 stage.
// (absPhase13 * ratio_2to1 - phase1) / PI_2
always @(posedge clk) begin
    phase1_r13 <= phase1_r12;
    abs_phase1_p2 <= abs_phase1_p1 >>> 1;
end

// 14 stage.
// round((absPhase13 * ratio_2to1 - phase1) / PI_2)
always @(posedge clk) begin
    phase1_r14 <= phase1_r13;
    abs_phase1_p3 <= round(abs_phase1_p2, 15);
end

// 15 stage.
// PI_2 * round((absPhase13 * ratio_2to1 - phase1) / PI_2)
always @(posedge clk) begin
    phase1_r15 <= phase1_r14;
    abs_phase1_p4 <= abs_phase1_p3 * 2;
end

// 16 stage.
// phase1 + PI_2 * round((absPhase13 * ratio_2to1 - phase1) / PI_2)
always @(posedge clk) begin
    // abs_phase1 <= abs_phase1_p4 + phase1_r15;
    abs_phase1 <= round(abs_phase1_p4 + phase1_r15, 6);
end

assign vld_o = vld_i_r[16];
// As the abs_phase large than 0, ignore the sign bit.
assign abs_phase_o = noise_r[16]? NOISE_CODE : abs_phase1[22:7];
assign last_o = last_i_r[16];

// Returns the integral value that is nearest to x, with halfway cases rounded away from zero.
function signed [23:0] round (input signed [23:0] x, input integer width);
    begin
        logic signed [23:0] x_abs, add_point5, point_5, abs_round;
        point_5 = 24'd1 << (width - 1);
        x_abs = x[23]? -x : x;
        add_point5 = x_abs + (point_5);
        abs_round = add_point5 & (24'hFFFFFF << width);
        round = x[23]? -abs_round : abs_round;
    end
endfunction

endmodule