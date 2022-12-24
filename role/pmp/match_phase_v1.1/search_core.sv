//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// search_core.sv
// 
// Description:
// Compare core. 
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.12.23  ff          Initial version
//****************************************************************

`timescale 1ns / 1ps

module search_core #(
    parameter DATA_WIDTH = 16,
    parameter WIN_SIZE = 32
) (
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic signed [DATA_WIDTH-1:0]    error_i [WIN_SIZE-1:0],
    input  logic signed [DATA_WIDTH-1:0]    pos_i   [WIN_SIZE-1:0],
    input  logic signed [DATA_WIDTH-1:0]    abs_phase1_pos_i,
    input  logic                            not_found_i,
    input  logic                            vld_i,
    input  logic                            tlast_i,

    output logic signed [DATA_WIDTH-1:0]    x0,
    output logic signed [DATA_WIDTH-1:0]    y_sub_y0,
    output logic signed [DATA_WIDTH-1:0]    y_sub_y1,
    output logic signed [DATA_WIDTH-1:0]    abs_phase1_pos_o,
    output logic                            not_found_o,
    output logic                            tlast_o,
    output logic                            vld_o
);

logic signed [DATA_WIDTH-1:0]   error_i_r           [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]   pos_i_r             [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]   abs_phase1_pos_i_r  [1:0];
logic        [1:0]              vld_i_r;
logic        [1:0]              tlast_i_r;
logic        [1:0]              not_found_i_r;

// Reg input.
always @(posedge clk) begin
    error_i_r <= error_i;
    pos_i_r <= pos_i;
    abs_phase1_pos_i_r[0] <= abs_phase1_pos_i;
    not_found_i_r[0] <= not_found_i;
end
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[0] <= 0;
        tlast_i_r[0] <= 0;
    end else begin
        vld_i_r[0] <= vld_i;
        tlast_i_r[0] <= tlast_i;
    end
end

// Solve problem.
always @(posedge clk) begin
    x0 <= pos_i_r[0];
    y_sub_y0 <= error_i_r[0];
    y_sub_y1 <= error_i_r[1];
    for (int i = 0; i < WIN_SIZE-1; i++) begin
        if(~error_i_r[i][DATA_WIDTH-1] & error_i_r[i+1][DATA_WIDTH-1]) begin
            x0 <= pos_i_r[i];
            y_sub_y0 <= error_i_r[i];
            y_sub_y1 <= error_i_r[i+1];
        end
    end
    abs_phase1_pos_i_r[1] <= abs_phase1_pos_i_r[0];
    not_found_i_r[1] <= not_found_i_r[0];
end
always @(posedge clk) begin
    if(~rst_n) begin
        vld_i_r[1] <= 0;
        tlast_i_r[1] <= 0;
    end else begin
        vld_i_r[1] <= vld_i_r[0];
        tlast_i_r[1] <= tlast_i_r[0];
    end
end

assign vld_o = vld_i_r[1];
assign tlast_o = tlast_i_r[1];
assign abs_phase1_pos_o = abs_phase1_pos_i_r[1];
assign not_found_o = not_found_i_r[1];

endmodule