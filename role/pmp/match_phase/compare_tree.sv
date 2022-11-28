`timescale 1ns / 1ps
//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// compare_tree.sv
// 
// Description:
// Compare tree. Calculate phase1 substract phase2 and pass the closest one's position and error.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.17  ff          Initial version
//****************************************************************

module compare_tree #(
    parameter DEPTH = 7,
    parameter LEVEL = 0,
    parameter DATA_WIDTH = 16
) (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic signed [DATA_WIDTH-1:0]    error_i [2**(DEPTH-LEVEL)-1:0],
    input  logic signed [DATA_WIDTH-1:0]    pos_i   [2**(DEPTH-LEVEL)-1:0],
    input  logic                            vld_i,

    output logic signed [DATA_WIDTH-1:0]    error_o,
    output logic signed [DATA_WIDTH-1:0]    pos_o,
    output logic                            vld_o
);
// Pre-calculations.
localparam TREE_WIDTH       = 2**(DEPTH-LEVEL);
localparam TREE_HALF_WIDTH  = TREE_WIDTH / 2;

logic signed [DATA_WIDTH-1:0]   error_i_r   [TREE_WIDTH-1:0];
logic signed [DATA_WIDTH-1:0]   pos_i_r     [TREE_WIDTH-1:0];
logic                           vld_i_r;
logic signed [DATA_WIDTH-1:0]   error_i0    [TREE_HALF_WIDTH-1:0];
logic signed [DATA_WIDTH-1:0]   pos_i0      [TREE_HALF_WIDTH-1:0];
logic signed [DATA_WIDTH-1:0]   error_i1    [TREE_HALF_WIDTH-1:0];
logic signed [DATA_WIDTH-1:0]   pos_i1      [TREE_HALF_WIDTH-1:0];

// Reg error_i, pos_i and vld_i.
always @(posedge clk) begin
    if(~rst_n)
        vld_i_r <= 'b0;
    else
        vld_i_r <= vld_i;
end
always @(posedge clk) begin
    error_i_r <= error_i;
    pos_i_r <= pos_i;
end

always @(*) begin
    for (int i = 0; i < TREE_HALF_WIDTH; i++) begin
        error_i0[i] = error_i_r [i*2];
        pos_i0[i] = pos_i_r [i*2];
        error_i1[i] = error_i_r [i*2+1];
        pos_i1[i] = pos_i_r [i*2+1];
    end
end

generate
// Separeate question.
logic signed [DATA_WIDTH-1:0]   error0;
logic signed [DATA_WIDTH-1:0]   pos0;
logic                           vld0;
logic signed [DATA_WIDTH-1:0]   error0_r;
logic signed [DATA_WIDTH-1:0]   pos0_r;
logic                           vld_r;
logic signed [DATA_WIDTH-1:0]   error1;
logic signed [DATA_WIDTH-1:0]   pos1;
logic                           vld1;
logic signed [DATA_WIDTH-1:0]   error1_r;
logic signed [DATA_WIDTH-1:0]   pos1_r;
logic signed [DATA_WIDTH-1:0]   compare;
logic                           submit_error0;
if(LEVEL < DEPTH - 1) begin
    compare_tree #(
        .DEPTH      (   DEPTH       ),
        .LEVEL      (   LEVEL+1     ),
        .DATA_WIDTH (   DATA_WIDTH  )
    ) compare_tree_recursion_0 (
        .clk        (   clk         ),
        .rst_n      (   rst_n       ),
        .vld_i      (   vld_i_r     ),
        .error_i    (   error_i0    ),
        .pos_i      (   pos_i0      ),

        .error_o    (   error0      ),
        .pos_o      (   pos0        ),
        .vld_o      (   vld0        )
    );

    compare_tree #(
        .DEPTH      (   DEPTH       ),
        .LEVEL      (   LEVEL+1     ),
        .DATA_WIDTH (   DATA_WIDTH  )
    ) compare_tree_recursion_1 (
        .clk        (   clk         ),
        .rst_n      (   rst_n       ),
        .vld_i      (   vld_i_r     ),
        .error_i    (   error_i1    ),
        .pos_i      (   pos_i1      ),

        .error_o    (   error1     ),
        .pos_o      (   pos1       ),
        .vld_o      (   vld1       )
    );
end else begin
    assign error0  = error_i0[0];
    assign pos0    = pos_i0[0];
    assign vld0    = vld_i_r;
    assign error1  = error_i1[0];
    assign pos1    = pos_i1[0];
    assign vld1    = vld_i_r;
end

// Solve problems.
// Reg results.
always @(posedge clk) begin
    error0_r <= error0;
    pos0_r <= pos0;
    vld_r <= vld0;
    error1_r <= error1;
    pos1_r <= pos1;
end
// Substract errors to compare.
always @(posedge clk) begin
    if(error1[DATA_WIDTH-1] == error0[DATA_WIDTH-1])
        compare <= error0 - error1;
    else
        compare <= error0 + error1;
end
always @(*) begin
    case ({error1_r[DATA_WIDTH-1], error0_r[DATA_WIDTH-1]})
        2'b00: submit_error0 = compare[DATA_WIDTH-1]? 1 : 0;
        2'b01: submit_error0 = compare[DATA_WIDTH-1]? 0 : 1;
        2'b10: submit_error0 = compare[DATA_WIDTH-1]? 1 : 0;
        2'b11: submit_error0 = compare[DATA_WIDTH-1]? 0 : 1;
    endcase
end
// Compare and submit.
always @(posedge clk) begin
    if(submit_error0) begin
        error_o <= error0_r;
        pos_o <= pos0_r;
    end else begin
        error_o <= error1_r;
        pos_o <= pos1_r;
    end
    vld_o <= vld_r;
end
endgenerate
endmodule