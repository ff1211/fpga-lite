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
    parameter N_IN_ONE = 4,
    parameter DEPTH = 7,
    parameter LEVEL = 0,
    parameter DATA_WIDTH = 16
) (
    input  logic                          clk     ,
    input  logic                          rst_n   ,
    input  logic signed [DATA_WIDTH-1:0]  error_i [N_IN_ONE**(DEPTH-LEVEL)-1:0],
    input  logic signed [DATA_WIDTH-1:0]  pos_i   [N_IN_ONE**(DEPTH-LEVEL)-1:0],
    input  logic                          vld_i   ,

    output logic signed [DATA_WIDTH-1:0]  error_o ,
    output logic signed [DATA_WIDTH-1:0]  pos_o   ,
    output logic                          vld_o   
);
// Pre-calculations.
localparam TREE_WIDTH   = N_IN_ONE**(DEPTH-LEVEL);
localparam GROUP_NUM    = TREE_WIDTH / N_IN_ONE;

logic signed [DATA_WIDTH-1:0]   error_g [GROUP_NUM-1:0];
logic signed [DATA_WIDTH-1:0]   pos_g   [GROUP_NUM-1:0];
logic        [GROUP_NUM-1:0]    vld_g;

genvar i;
generate
// Separeate question.
for (i = 0; i < GROUP_NUM; i++) begin
    if(LEVEL < DEPTH - 1) begin
        logic signed [DATA_WIDTH-1:0]   error_i_g   [N_IN_ONE-1:0];
        logic signed [DATA_WIDTH-1:0]   pos_i_g     [N_IN_ONE-1:0];
        logic                           vld_i_g;
        compare_tree #(
            .N_IN_ONE   (   N_IN_ONE    ),
            .DEPTH      (   DEPTH       ),
            .LEVEL      (   LEVEL+1     ),
            .DATA_WIDTH (   DATA_WIDTH  )
        ) compare_tree_recursion (
            .clk        (   clk         ),
            .rst_n      (   rst_n       ),
            .vld_i      (   vld_i_g     ),
            .error_i    (   error_i_g   ),
            .pos_i      (   pos_i_g     ),

            .error_o    (   error_g[i]  ),
            .pos_o      (   pos_g[i]    ),
            .vld_o      (   vld_g[i]    )
        );
        assign error_i_g = error_i[i*N_IN_ONE+:N_IN_ONE];
        assign pos_i_g = pos_i[i*N_IN_ONE+:N_IN_ONE];
        assign vld_i_g = vld_i;
    end else begin
        assign error_g = error_i;
        assign pos_g = pos_i;
        assign vld_g = {{N_IN_ONE}vld_i};
    end
end

// Solve problem.
for (i = 0; i < GROUP_NUM; i++) begin
    logic signed [DATA_WIDTH-1:0] error_t;
    logic signed [DATA_WIDTH-1:0] pos_t;

    always @(*) begin
        error_t = error_g[0];
        pos_t = pos_g[0];
        for (int j = 1; j < N_IN_ONE; j++)
            if(abs(error_g[j]) < abs(error_t)) begin
                error_t = error_g[j];
                pos_t = pos_g[j];
            end else begin
                error_t = error_t;
                pos_t = pos_t;
            end
    end
    
    always@(posedge clk) begin
        error_o[i] <= error_t;
        pos_o[i] <= pos_t;
        vld_o <= vld_g[0];
    end
end
endgenerate

function logic signed [DATA_WIDTH-1:0] abs;
    input logic signed [DATA_WIDTH-1:0] x;
    begin
        abs = x[DATA_WIDTH]? -x : x;
    end
endfunction

endmodule
