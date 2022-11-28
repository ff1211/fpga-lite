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
    parameter DATA_WIDTH = 16,
    parameter RATIO_3TO2 = 8,
    parameter RATIO_2TO1 = 8
) (
    input                           clk,
    input                           rst_n,
    input                           vld_i,
    input signed [DATA_WIDTH-1:0]   phase1_i,
    input signed [DATA_WIDTH-1:0]   phase2_i,
    input signed [DATA_WIDTH-1:0]   phase3_i,
    input                           tlast_i,
    output                          vld_o,
    output signed [DATA_WIDTH-1:0]  abs_phase_o,
    output                          tlast_o
);

localparam PI_2_3QN_24B     = 24'b01100100_10000111_11101101;
localparam PI_2_10QN_24B    = 24'b00000000_11001001_00001111;
localparam POINT_5_3QN_24B  = 24'b00001000_00000000_00000000;
localparam POINT_5_10QN_24B = 24'b00000000_00010000_00000000;

logic signed [23:0] phase1;
logic signed [23:0] phase2;
logic signed [23:0] phase3;
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

logic signed [23:0] abs_phase13_p0;
logic signed [23:0] abs_phase13_p1;
logic signed [36:0] abs_phase13_p1_s;
logic signed [23:0] abs_phase13_p2;
logic signed [23:0] abs_phase13_p3;
logic signed [10:0] abs_phase13_p3_s;
logic signed [23:0] abs_phase13_p4;
logic signed [23:0] abs_phase13;

logic signed [23:0] abs_phase1_p0;
logic signed [23:0] abs_phase1_p1;
logic signed [36:0] abs_phase1_p1_s;
logic signed [23:0] abs_phase1_p2;
logic signed [23:0] abs_phase1_p3;
logic signed [10:0] abs_phase1_p3_s;
logic signed [23:0] abs_phase1_p4;
logic signed [23:0] abs_phase1;
logic signed [23:0] abs_phase1_s;

logic               div_0_dout_tvalid;
logic               div_0_dout_tlast;
logic  [63:0]       div_0_dout_tdata;
logic  [47:0]       div_0_dout_tuser;
logic               div_1_dout_tvalid;
logic               div_1_dout_tlast;
logic  [63:0]       div_1_dout_tdata;
logic  [47:0]       div_1_dout_tuser;

logic  [17:0]    vld_i_r;
logic  [17:0]    tlast_i_r;

// Input
// Fixed-point twos complement number with an integer width of 3 bits (2QN format)

// Buffer pixel data and extent it to 32bits.
// Fixed-point twos complement numbers with an integer width of 11 bits (10QN format).
// Maximum 1024 rad.
assign phase1 = phase1_i;
assign phase2 = phase2_i;
assign phase3 = phase3_i;
// Fixed-point twos complement numbers with an integer width of 4 bits (3QN format).
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[0] <= 0;
        tlast_i_r[0] <= 0;
    end else begin
        phase1_r0 <= phase1;
        phase2_r0 <= phase2;
        phase3_r0 <= phase3;
        vld_i_r[0] <= vld_i;
        tlast_i_r[0] <= tlast_i;
    end
end

// Calculate phase substraction.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[1] <= 0;
        tlast_i_r[1] <= 0;
    end else begin
        phase1_r1 <= phase1_r0;
        phase1sub3 <= phase1_r0 - phase3_r0;
        phase2sub3 <= phase2_r0 - phase3_r0;
        vld_i_r[1] <= vld_i_r[0];
        tlast_i_r[1] <= tlast_i_r[0];
    end
end

// Heterodyne 13 and 23
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[2] <= 0;
        tlast_i_r[2] <= 0;
    end else begin
        phase1_r2 <= phase1_r1;
        phase13 <= phase1sub3[23]? (phase1sub3 + PI_2_10QN_24B) : phase1sub3;
        phase23 <= phase2sub3[23]? (phase2sub3 + PI_2_10QN_24B) : phase2sub3;
        vld_i_r[2] <= vld_i_r[1];
        tlast_i_r[2] <= tlast_i_r[1];
    end
end

// Register phase13.
// Substract phase13 and phase23.
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[3] <= 0;
        tlast_i_r[3] <= 0;
    end else begin
        phase1_r3 <= phase1_r2;
        phase13_r0 <= phase13;
        phase13sub23 <= phase13 - phase23;
        vld_i_r[3] <= vld_i_r[2];
        tlast_i_r[3] <= tlast_i_r[2];
    end
end

// Register phase13_r0.
// Heterodyne 123
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[4] <= 0;
        tlast_i_r[4] <= 0;
    end else begin
        phase1_r4 <= phase1_r3;
        phase13_r1 <= phase13_r0;
        phase123 <= phase13sub23[23]? (phase13sub23 + PI_2_10QN_24B) : phase13sub23;
        vld_i_r[4] <= vld_i_r[3];
        tlast_i_r[4] <= tlast_i_r[3];
    end
end

// absPhase13 = phase13 + PI_2 * round((phase123 * ratio_3to2 - phase13) / PI_2);
// absPhaseMap.at<TYPE>(i, j) = phase1 + PI_2 * round((absPhase13 * ratio_2to1 - phase1) / PI_2);

// Calculate phase123 * ratio_3to2
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[5] <= 0;
        tlast_i_r[5] <= 0;
    end else begin
        phase1_r5 <= phase1_r4;
        phase13_r2 <= phase13_r1;
        abs_phase13_p0 <= phase123 * RATIO_3TO2;
        vld_i_r[5] <= vld_i_r[4];
        tlast_i_r[5] <= tlast_i_r[4];
    end
end

// phase123 * ratio_3to2 - phase13
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [6] <= 0;
        tlast_i_r   [6] <= 0;
    end else begin
        phase1_r5 <= phase1_r4;
        phase13_r2 <= phase13_r1;
        abs_phase13_p1 <= abs_phase13_p0 - phase13_r1;
        vld_i_r     [6] <= vld_i_r  [5];
        tlast_i_r   [6] <= tlast_i_r[5];
    end
end

// Shift it
// (phase123 * ratio_3to2 - phase13) / PI_2
assign abs_phase13_p1_s = {abs_phase13_p1, 13'b0};
div_gen_0 div_gen_inst_0 (
    .aclk                   (   clk     ),
    .aresetn                (   rst_n   ),   
    .s_axis_divisor_tvalid  (   vld_i_r     [6]         ),
    .s_axis_divisor_tdata   (   PI_2_10QN_24B           ),      // input wire [23 : 0] s_axis_divisor_tdata
    .s_axis_dividend_tuser  (   {phase1_r5, phase13_r2} ),    // input wire [47 : 0] 
    .s_axis_dividend_tvalid (   vld_i_r     [6]         ),
    .s_axis_dividend_tlast  (   tlast_i_r   [6]         ),
    .s_axis_dividend_tdata  (   {3'b0, abs_phase13_p1_s}),    // input wire [39 : 0] s_axis_dividend_tdata
    .m_axis_dout_tvalid     (   div_0_dout_tvalid       ),
    .m_axis_dout_tlast      (   div_0_dout_tlast        ),
    .m_axis_dout_tuser      (   div_0_dout_tuser        ),            // output wire [47 : 0] m_axis_dout_tuser
    .m_axis_dout_tdata      (   div_0_dout_tdata        )            // output wire [63 : 0] m_axis_dout_tdata
);

always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [7] <= 0;
        tlast_i_r   [7] <= 0;
    end else begin
        phase1_r6 <= div_0_dout_tuser[47:24];
        phase13_r3 <= div_0_dout_tuser[23:0];
        abs_phase13_p2 <= div_0_dout_tdata[47:24];
        vld_i_r     [7] <= div_0_dout_tvalid;
        tlast_i_r   [7] <= div_0_dout_tlast;
    end
end

//(phase123 * ratio_3to2 - phase13) / PI_2 + 0.5
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [8] <= 0;
        tlast_i_r   [8] <= 0;
    end else begin
        phase1_r7 <= phase1_r6;
        phase13_r4 <= phase13_r3;
        abs_phase13_p3 <= abs_phase13_p2 + POINT_5_10QN_24B;
        vld_i_r     [8] <= vld_i_r  [7];
        tlast_i_r   [8] <= tlast_i_r[7];
    end
end
// PI_2 * round((phase123 * ratio_3to2 - phase13) / PI_2)
assign abs_phase13_p3_s = abs_phase13_p3[23:13];
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [9] <= 0;
        tlast_i_r   [9] <= 0;
    end else begin
        phase1_r8 <= phase1_r7;
        phase13_r5 <= phase13_r4;
        abs_phase13_p4 <= abs_phase13_p3_s * PI_2_10QN_24B;
        vld_i_r     [9] <= vld_i_r      [8];
        tlast_i_r   [9] <= tlast_i_r    [8];
    end
end
// phase13 + PI_2 * round((phase123 * ratio_3to2 - phase13) / PI_2)
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [10] <= 0;
        tlast_i_r   [10] <= 0;
    end else begin
        phase1_r9 <= phase1_r8;
        abs_phase13 <= abs_phase13_p4 + phase13_r5;
        vld_i_r     [10] <= vld_i_r     [9];
        tlast_i_r   [10] <= tlast_i_r   [9];
    end
end

// phase1 + PI_2 * round((absPhase13 * ratio_2to1 - phase1) / PI_2);
// Calculate absPhase13 * ratio_2to1
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [11] <= 0;
        tlast_i_r   [11] <= 0;
    end else begin
        phase1_r10 <= phase1_r9;
        abs_phase1_p0 <= abs_phase13 * RATIO_2TO1;
        vld_i_r     [11] <= vld_i_r     [10];
        tlast_i_r   [11] <= tlast_i_r   [10];
    end
end
// Calculate absPhase13 * ratio_2to1 - phase1
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [12] <= 0;
        tlast_i_r   [12] <= 0;
    end else begin
        phase1_r10 <= phase1_r9;
        abs_phase1_p1 <= abs_phase1_p0 - phase1_r7;
        vld_i_r     [12] <= vld_i_r     [11];
        tlast_i_r   [12] <= tlast_i_r   [11];
    end
end
// Shift it 
// (absPhase13 * ratio_2to1 - phase1) / PI_2
assign abs_phase1_p1_s = {abs_phase1_p1, 13'b0};
div_gen_0 div_gen_inst_1 (
    .aclk                   (   clk     ),
    .aresetn                (   rst_n   ),                               
    .s_axis_divisor_tvalid  (   vld_i_r     [12]        ),
    .s_axis_divisor_tdata   (   PI_2_10QN_24B           ),      // input wire [23 : 0] s_axis_divisor_tdata
    .s_axis_dividend_tuser  (   {phase1_r10, 24'b0}     ),    // input wire [47 : 0] 
    .s_axis_dividend_tvalid (   vld_i_r     [12]        ),
    .s_axis_dividend_tlast  (   tlast_i_r   [12]        ),
    .s_axis_dividend_tdata  (   {3'b0, abs_phase1_p1_s} ),    // input wire [39 : 0] s_axis_dividend_tdata
    .m_axis_dout_tvalid     (   div_1_dout_tvalid       ),
    .m_axis_dout_tlast      (   div_1_dout_tlast        ),
    .m_axis_dout_tuser      (   div_1_dout_tuser        ),            // output wire [47 : 0] m_axis_dout_tuser
    .m_axis_dout_tdata      (   div_1_dout_tdata        )            // output wire [63 : 0] m_axis_dout_tdata
);

always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [13] <= 0;
        tlast_i_r   [13] <= 0;
    end else begin
        phase1_r11 <= div_1_dout_tuser[47:24];
        abs_phase1_p2 <= div_1_dout_tdata[47:24];
        vld_i_r     [13] <= div_1_dout_tvalid;
        tlast_i_r   [13] <= div_1_dout_tlast;
    end
end

// (absPhase13 * ratio_2to1 - phase1) / PI_2 + 0.5
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [14] <= 0;
        tlast_i_r   [14] <= 0;
    end else begin
        phase1_r12 <= phase1_r11;
        abs_phase1_p3 <= abs_phase1_p2 + POINT_5_10QN_24B;
        vld_i_r     [14] <= vld_i_r     [13];
        tlast_i_r   [14] <= tlast_i_r   [13];
    end
end
// PI_2 * round((absPhase13 * ratio_2to1 - phase1) / PI_2)
assign abs_phase1_p3_s = abs_phase1_p3[23:13];
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [15] <= 0;
        tlast_i_r   [15] <= 0;
    end else begin
        phase1_r13 <= phase1_r12;
        abs_phase1_p4 <= abs_phase1_p3_s * PI_2_10QN_24B;
        vld_i_r     [15] <= vld_i_r     [14];
        tlast_i_r   [15] <= tlast_i_r   [14];
    end
end
// phase1 + PI_2 * round((absPhase13 * ratio_2to1 - phase1) / PI_2)
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r     [16] <= 0;
        tlast_i_r   [16] <= 0;
    end else begin
        abs_phase1 <= abs_phase1_p4 + phase1_r13;
        vld_i_r     [16] <= vld_i_r     [15];
        tlast_i_r   [16] <= tlast_i_r   [15];
    end
end

assign vld_o = vld_i_r[14];
assign abs_phase_o = abs_phase1[23-:DATA_WIDTH];
assign tlast_o = tlast_i_r[14];

endmodule