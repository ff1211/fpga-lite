//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// shift_reg.sv
// 
// Description:
// Shift register
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.12.11  ff          Initial version
//****************************************************************

`timescale 1ns/1ps

module shift_reg #(
    parameter DATA_WIDTH = 16,
    parameter STAGES = 8
) (
    input                   clk,
    input                   en,
    input  [DATA_WIDTH-1:0] din,
    output [DATA_WIDTH-1:0] dout
);

logic [STAGES-1:0][DATA_WIDTH-1:0] din_r;

always @(posedge clk) begin
    if(en) begin
        din_r[0] <= din;
        for (int i = 1; i < STAGES; i++)
            din_r[i] <= din_r[i-1];
    end else
        din_r <= din_r;
end
assign dout = din_r[STAGES-1];
endmodule