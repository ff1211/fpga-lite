//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// axis_xbar.sv
// 
// Description:
// AXI Stream crossbar.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.25  ff          Initial version
//****************************************************************

module axis_xbar #(
    parameter CHANNEL = 2,
    parameter DATA_WIDTH = 32
) (
    input  logic [CHANNEL-1:0][DATA_WIDTH-1:0]  s_axis_tdata,
    input  logic                                s_axis_tvalid,
    output logic                                s_axis_tready,
    input  logic                                s_axis_tlast,
    
    output logic [DATA_WIDTH-1:0]               m_axis_tdata,
    output logic                                m_axis_tvalid,
    input  logic                                m_axis_tready,
    output logic                                m_axis_tlast,

    input  logic [CHANNEL-1:0]                  switch
);

always @(*) begin
    for(int i = 0; i < CHANNEL; ++i)
        if(switch[i]) begin
            m_axis_tdata  = s_axis_tdata [i];
            m_axis_tvalid = s_axis_tvalid[i];
            s_axis_tready[i] = m_axis_tlast;
            m_axis_tlast  = s_axis_tlast [i];
        end
end

endmodule