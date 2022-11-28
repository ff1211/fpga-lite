//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// assembler.sv
// 
// Description:
// Assembler that take N data beats and a tag in.
// Based on the tag, it will select corresponding data beats and send it to output.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.25  ff          Initial version
//****************************************************************

module assembler #(
    parameter DATA_WIDTH = 16,
    parameter TAG_WIDTH = 8,
    parameter TAG_CATAGORY = 4,
    parameter BEAT_SIZE = 8
) (
    input clk,
    input rst_n,

    input  [TAG_WIDTH-1:0]                      tag_i,
    input  [TAG_CATAGORY-1:0][DATA_WIDTH-1:0]   data_i,
    input                                       tlast_i,
    input                                       vld_i,

    output logic [DATA_WIDTH-1:0]               data_o,
    output logic                                tlast_o,
    output logic                                vld_o
);

logic [TAG_WIDTH-1:0]                       tag_i_r;
logic [TAG_CATAGORY-1:0][DATA_WIDTH-1:0]    data_i_r;
logic                                       tlast_i_r;
logic                                       vld_i_r;

// Reg inputs.
always @(posedge clk) begin
    if(~rst_n)
        vld_i_r <= 0;

    tag_i_r <= tag_i;
    data_i_r <= data_i;
    tlast_i_r <= tlast_i;
    vld_i_r <= vld_i;
end

always @(*) begin
    if(tag_i_r < TAG_CATAGORY)
        data_o = data_i_r[tag_i_r];
    else
        data_o = data_i_r[0];
        
    tlast_o = tlast_i_r;
    vld_o = vld_i_r;
end

endmodule

