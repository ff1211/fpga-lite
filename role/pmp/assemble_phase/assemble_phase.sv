//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// assemble_phase.sv
// 
// Description:
// Module used to assemble different phases to a single map together according to their tags.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.25  ff          Initial version
//****************************************************************

module assemble_phase #(
    parameter DATA_WIDTH = 16,
    parameter TAG_WIDTH = 8,
    parameter TAG_CATAGORY = 4,
    parameter BEAT_SIZE = 8,
    parameter BUFFER_DEPTH = 512
) (
    input aclk,
    input aresetn,

    input  logic [BEAT_SIZE*DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                            s_axis_tvalid,
    output logic                            s_axis_tready,
    input  logic                            s_axis_tlast,
    
    output logic [BEAT_SIZE*DATA_WIDTH-1:0] m_axis_tdata,
    output logic                            m_axis_tvalid,
    input  logic                            m_axis_tready,
    output logic                            m_axis_tlast
);

localparam BEAT_WIDTH = BEAT_SIZE*DATA_WIDTH;
localparam TAG_PART_WIDTH = BEAT_WIDTH/(DATA_WIDTH/TAG_WIDTH);

logic [TAG_CATAGORY:0]                  switch;
logic [7:0]                             buf_rd_cnt;

logic [TAG_CATAGORY:0]                  input_buf_wr_en;
logic [TAG_CATAGORY:0]                  input_buf_rd_en;
logic [BEAT_WIDTH:0]                    input_buf_din;
logic [TAG_CATAGORY:0]                  input_buf_empty;
logic [TAG_CATAGORY:0]                  input_buf_pfull;
logic [TAG_CATAGORY:0][BEAT_WIDTH:0]    input_buf_dout;

logic                                   output_buf_wr_en;
logic                                   output_buf_rd_en;
logic [BEAT_WIDTH:0]                    output_buf_din;
logic                                   output_buf_empty;
logic                                   output_buf_pfull;
logic [BEAT_WIDTH:0]                    output_buf_dout;

logic                                   vld_i;
logic                                   tlast_i;
logic [BEAT_SIZE-1:0]                   vld_o;
logic [BEAT_SIZE-1:0]                   tlast_o;
logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   data_o;

// Control input switch based on tlast signal.
always @(posedge aclk) begin
    if(~aresetn)
        switch <= 'b1;
    else if(s_axis_tready & s_axis_tvalid & s_axis_tlast)
        switch <= {switch[TAG_CATAGORY-1:0], switch[TAG_CATAGORY]};
end

// Generate input fifo.
genvar i, k;
generate
for (i = 0; i < TAG_CATAGORY+1; ++i) begin
    sync_fifo #(
        .FIFO_DEPTH         (  BUFFER_DEPTH ),
        .PROG_FULL_THRESH   (  BUFFER_DEPTH-10 ),
        .DATA_WIDTH         (  BEAT_WIDTH+1 ),
        .READ_MODE          (  "fwft"       ),
        .READ_LATENCY       (   0           )
    ) input_fifo (
        .clk    (   aclk    ),
        .rst_n  (   aresetn ),
    
        .wr_en  (   input_buf_wr_en[i]  ),
        .rd_en  (   input_buf_rd_en[i]  ),
        .din    (   input_buf_din       ),
        .dout   (   input_buf_dout[i]   ),

        .empty  (   input_buf_empty[i]  ),
        .pfull  (   input_buf_pfull[i]  )
    );
    assign input_buf_din = {s_axis_tlast, s_axis_tdata};
    //  
    if(i != TAG_CATAGORY)
        assign input_buf_rd_en[i] = vld_i;
    else
        assign input_buf_rd_en[i] = (buf_rd_cnt == DATA_WIDTH/TAG_WIDTH-1);
end
// Fifo control signals.
always@(*) begin
    s_axis_tready = (input_buf_pfull == 0);
    for (int i = 0; i < TAG_CATAGORY+1; ++i)
        input_buf_wr_en[i] = switch[i] & s_axis_tvalid & s_axis_tready;
end

always @(posedge aclk) begin
    if(~aresetn)
        buf_rd_cnt <= 0;
    else if(buf_rd_cnt == DATA_WIDTH/TAG_WIDTH-1)
        buf_rd_cnt <= 0;
    else if(input_buf_rd_en[0])
        buf_rd_cnt <= buf_rd_cnt + 1;
    else
        buf_rd_cnt <= buf_rd_cnt;
end
endgenerate

// Generate classifier.
generate
logic [BEAT_SIZE-1:0][TAG_WIDTH-1:0] tag_i;
assign tag_i = input_buf_dout[TAG_CATAGORY][buf_rd_cnt*TAG_PART_WIDTH+:TAG_PART_WIDTH];

for (i = 0; i < BEAT_SIZE; ++i) begin
    logic [TAG_CATAGORY-1:0][DATA_WIDTH-1:0] data_i;

    for(k = 0; k < TAG_CATAGORY; k++)
        assign data_i[k] = input_buf_dout[k][i*DATA_WIDTH+:DATA_WIDTH];
    
    classifier #(
        .DATA_WIDTH    (    DATA_WIDTH      ),
        .TAG_WIDTH     (    TAG_WIDTH       ),
        .TAG_CATAGORY  (    TAG_CATAGORY    ),
        .BEAT_SIZE     (    BEAT_SIZE       )
    ) classifier_inst (
        .clk        (   aclk        ),
        .rst_n      (   aresetn     ),

        .tag_i      (   tag_i[i]    ),
        .data_i     (   data_i      ),
        .tlast_i    (   tlast_i     ),
        .vld_i      (   vld_i       ),

        .data_o     (   data_o[i]   ),
        .tlast_o    (   tlast_o[i]  ),
        .vld_o      (   vld_o[i]    )
    );
end
endgenerate
assign vld_i = ~input_buf_empty[TAG_CATAGORY] & ~output_buf_pfull;
assign tlast_i = input_buf_dout[0][BEAT_WIDTH];

// Output fifo.
sync_fifo #(
    .FIFO_DEPTH         (  BUFFER_DEPTH ),
    .PROG_FULL_THRESH   (  BUFFER_DEPTH-10 ),
    .DATA_WIDTH         (  BEAT_WIDTH+1 ),
    .READ_MODE          (  "fwft"       ),
    .READ_LATENCY       (   0           )
) output_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   output_buf_wr_en    ),
    .rd_en  (   output_buf_rd_en    ),
    .din    (   output_buf_din      ),
    .dout   (   output_buf_dout     ),

    .empty  (   output_buf_empty    ),
    .pfull  (   output_buf_pfull    )
);

assign output_buf_wr_en = vld_o[0];
assign output_buf_rd_en = m_axis_tready & m_axis_tvalid;
assign output_buf_din = {tlast_o[0], data_o};
assign m_axis_tdata = output_buf_dout[BEAT_WIDTH-1:0];
assign m_axis_tvalid = ~output_buf_empty;
assign m_axis_tlast = output_buf_dout[BEAT_WIDTH];

endmodule