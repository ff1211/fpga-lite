`timescale 1ns / 1ps
//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// compare_tree.sv
// 
// Description:
// Compare tree. Find the minimum value.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.17  ff          Initial version
//****************************************************************

module compare_tree #(
    parameter DEPTH = 7,
    parameter USER_WIDTH = 1,
    parameter DATA_WIDTH = 16,
    parameter TYPE = "min"
) (
    input  logic                                        clk,
    input  logic                                        rst_n,

    input  logic signed [DATA_WIDTH-1:0]                compare_val_i [2**DEPTH-1:0],
    input  logic        [2**DEPTH-1:0][USER_WIDTH-1:0]  user_val_i,
    input  logic                                        vld_i,

    output logic signed [DATA_WIDTH-1:0]                compare_val_o,
    output logic        [USER_WIDTH-1:0]                user_val_o,
    output logic                                        vld_o
);

logic signed [DATA_WIDTH-1:0]                   compare_val_i_r [2**DEPTH-1:0];
logic        [2**DEPTH-1:0][USER_WIDTH-1:0]     user_val_i_r;
logic                                           vld_i_r;

// Reg input.
always @(posedge clk) begin
    if(~rst_n)
        vld_i_r <= 'b0;
    else
        vld_i_r <= vld_i;
end
always @(posedge clk) begin
    compare_val_i_r <= compare_val_i;
    user_val_i_r <= user_val_i;
end

generate
// If depth == 0, just output.
if(DEPTH == 0) begin
    always @(*) begin
        compare_val_o = compare_val_i_r[0];
        user_val_o = user_val_i_r;
        vld_o = vld_i_r;
    end
end else begin
    // Else separate the problem to two sub-module and make a conclusion.
    logic signed [DATA_WIDTH-1:0]                   compare_val0 [2**(DEPTH-1)-1:0];
    logic        [2**(DEPTH-1)-1:0][USER_WIDTH-1:0] user_val0;
    logic                                           vld0;
    logic signed [DATA_WIDTH-1:0]                   compare_val0_o;
    logic        [USER_WIDTH-1:0]                   user_val0_o;
    logic                                           vld0_o;
    logic signed [DATA_WIDTH-1:0]                   compare_val1 [2**(DEPTH-1)-1:0];
    logic        [2**(DEPTH-1)-1:0][USER_WIDTH-1:0] user_val1;
    logic                                           vld1;
    logic signed [DATA_WIDTH-1:0]                   compare_val1_o;
    logic        [USER_WIDTH-1:0]                   user_val1_o;
    logic                                           vld1_o;
    logic signed [DATA_WIDTH-1:0]                   devation;
    // If 0, submit val0, else submit val1.
    logic                                           compare_result;

    assign compare_val0 = compare_val_i_r[0+:2**(DEPTH-1)];
    assign compare_val1 = compare_val_i_r[2**(DEPTH-1)+:2**(DEPTH-1)];
    assign user_val0 = user_val_i_r[0+:2**(DEPTH-1)];
    assign user_val1 = user_val_i_r[2**(DEPTH-1)+:2**(DEPTH-1)];
    assign vld0 = vld_i_r;
    assign vld1 = vld_i_r;

    compare_tree #(
        .DEPTH      (   DEPTH-1     ),
        .USER_WIDTH (   USER_WIDTH  ),
        .DATA_WIDTH (   DATA_WIDTH  )
    ) compare_tree_inst_0(
        .clk            (   clk     ),
        .rst_n          (   rst_n   ),

        .compare_val_i  (   compare_val0    ),
        .user_val_i     (   user_val0       ),
        .vld_i          (   vld0            ),

        .compare_val_o  (   compare_val0_o  ),
        .user_val_o     (   user_val0_o     ),
        .vld_o          (   vld0_o          )
    );

    compare_tree #(
        .DEPTH      (   DEPTH-1     ),
        .USER_WIDTH (   USER_WIDTH  ),
        .DATA_WIDTH (   DATA_WIDTH  )
    ) compare_tree_inst_1(
        .clk            (   clk     ),
        .rst_n          (   rst_n   ),

        .compare_val_i  (   compare_val1    ),
        .user_val_i     (   user_val1       ),
        .vld_i          (   vld1            ),

        .compare_val_o  (   compare_val1_o  ),
        .user_val_o     (   user_val1_o     ),
        .vld_o          (   vld1_o          )
    );

    // Substract errors to compare.
    always @(*) begin
        if(compare_val1_o[DATA_WIDTH-1] == compare_val0_o[DATA_WIDTH-1])
            devation = compare_val0_o - compare_val1_o;
        else
            devation = compare_val0_o + compare_val1_o;
        if(TYPE == "min") 
            case ({compare_val1_o[DATA_WIDTH-1], compare_val0_o[DATA_WIDTH-1]})
                2'b00: compare_result = devation[DATA_WIDTH-1]? 0 : 1;
                2'b01: compare_result = devation[DATA_WIDTH-1]? 1 : 0;
                2'b10: compare_result = devation[DATA_WIDTH-1]? 0 : 1;
                2'b11: compare_result = devation[DATA_WIDTH-1]? 1 : 0;
            endcase
        else if (TYPE == "max")
            case ({compare_val1_o[DATA_WIDTH-1], compare_val0_o[DATA_WIDTH-1]})
                2'b00: compare_result = devation[DATA_WIDTH-1]? 1 : 0;
                2'b01: compare_result = devation[DATA_WIDTH-1]? 0 : 1;
                2'b10: compare_result = devation[DATA_WIDTH-1]? 1 : 0;
                2'b11: compare_result = devation[DATA_WIDTH-1]? 0 : 1;
            endcase
    end

    // Compare and submit.
    always @(posedge clk) begin
        compare_val_o <= compare_result? compare_val1_o : compare_val0_o;
        user_val_o <= compare_result? user_val1_o : user_val0_o;
        vld_o <= vld0_o;
    end
end
endgenerate

endmodule