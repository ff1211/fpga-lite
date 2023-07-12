//****************************************************************
// Copyright 2023 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// remap.sv
// 
// Description:
// Remap core top module.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2023.02.24  ff          Initial version
//****************************************************************

module remap #(
    parameter AXIS_DWIDTH = 128,
    parameter COLS = 1280,
    parameter ROWS = 1024,
    parameter INTERVAL = 16,
    parameter MAX_DISTANCE = 32
) (
    input  logic                    aclk,
    input  logic                    aresetn,

    input  logic [AXIS_DWIDTH-1:0]  s_axis_tdata,
    input  logic                    s_axis_tvalid,
    output logic                    s_axis_tready,
    input  logic                    s_axis_tlast,
    
    output logic [AXIS_DWIDTH-1:0]  m_axis_tdata,
    output logic                    m_axis_tvalid,
    input  logic                    m_axis_tready,
    output logic                    m_axis_tlast
);

localparam RAM_AWIDTH = $clog2(AXIS_DWIDTH);
localparam INPUT_BUF_DEPTH = COLS/AXIS_DWIDTH;

logic                   even_ram_wr_ena;
logic [AXIS_DWIDTH-1:0] even_ram_dina;
logic [RAM_AWIDTH-1:0]  even_ram_addra;
logic [AXIS_DWIDTH-1:0] even_ram_douta;
logic                   even_ram_wr_enb;
logic [AXIS_DWIDTH-1:0] even_ram_dinb;
logic [RAM_AWIDTH-1:0]  even_ram_addrb;
logic [AXIS_DWIDTH-1:0] even_ram_doutb;
logic                   odd_ram_wr_ena;
logic [AXIS_DWIDTH-1:0] odd_ram_dina;
logic [RAM_AWIDTH-1:0]  odd_ram_addra;
logic [AXIS_DWIDTH-1:0] odd_ram_douta;
logic                   odd_ram_wr_enb;
logic [AXIS_DWIDTH-1:0] odd_ram_dinb;
logic [RAM_AWIDTH-1:0]  odd_ram_addrb;
logic [AXIS_DWIDTH-1:0] odd_ram_doutb;
logic input_buf_wr_en;
logic input_buf_rd_en;
logic input_buf_din;
logic input_buf_empty;
logic input_buf_pfull;
logic input_buf_dout;

sync_fifo #(
    .FIFO_DEPTH         (           ),
    .PROG_FULL_THRESH   (  BUFFER_DEPTH-10          ),
    .DATA_WIDTH         (  USER_WIDTH*ISSUE_WIDTH   ),
    .READ_MODE          (  "fwft"                   ),
    .READ_LATENCY       (   0                       )
) input_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   dis_buf_wr_en   ),
    .rd_en  (   dis_buf_rd_en   ),
    .din    (   dis_buf_din     ),
    .dout   (   dis_buf_dout    ),

    .empty  (   dis_buf_empty   ),
    .pfull  (   dis_buf_pfull   )
);

tdual_ram #(
    .ADDR_WIDTH_A          (    RAM_AWIDTH      ),
    .DATA_WIDTH_A          (    AXIS_DATA_WIDTH ),
    .READ_LATENCY_A        (    2               ),
    .BYTE_WRITE_WIDTH_A    (    AXIS_DATA_WIDTH ),
    .ADDR_WIDTH_B          (    RAM_AWIDTH      ),
    .DATA_WIDTH_B          (    AXIS_DATA_WIDTH ),
    .READ_LATENCY_B        (    2               ),
    .BYTE_WRITE_WIDTH_B    (    AXIS_DATA_WIDTH )
) even_row_ram (
    .clk        (   aclk    ),
    .rst_n      (   aresetn ),
    // A port.
    .enablea    (   1'b1    ),
    .wr_ena     (   even_ram_wr_ena ),
    .dina       (   even_ram_dina   ),
    .addra      (   even_ram_addra  ),
    .douta      (   even_ram_douta  ),
    // B port.
    .enableb    (   1'b1    ),
    .wr_enb     (   even_ram_wr_enb ),
    .dinb       (   even_ram_dinb   ),
    .addrb      (   even_ram_addrb  ),
    .doutb      (   even_ram_doutb  )
);
endmodule