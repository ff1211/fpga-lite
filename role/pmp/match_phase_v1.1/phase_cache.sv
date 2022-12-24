//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// phase_cache.sv
// 
// Description:
// Cache to store phase which will be matched.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.14  ff          Initial version
//****************************************************************

`timescale 1ns / 1ps

module phase_cache #(
    parameter ROW_SIZE = 1280,
    parameter WIN_SIZE = 128,
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16,
    parameter READ_LATENCY = 2
) (
    input  logic                                    aclk,
    input  logic                                    aresetn,

    input  logic [BEAT_SIZE*DATA_WIDTH-1:0]         s_axis_tdata,
    input  logic                                    s_axis_tvalid,
    output logic                                    s_axis_tready,
    input  logic                                    s_axis_tlast,

    input  logic [BEAT_SIZE-1:0][$clog2(ROW_SIZE/WIN_SIZE)-1:0] cache_addr,
    output logic [BEAT_SIZE-1:0][WIN_SIZE*DATA_WIDTH-1:0]       cache_dout
);
// Pre-calculations.
localparam BEAT_WIDTH = BEAT_SIZE * DATA_WIDTH;
localparam BEAT_NUM = ROW_SIZE / BEAT_SIZE;
localparam CACHE_WIDTH = WIN_SIZE * DATA_WIDTH;
localparam ADDR_WIDTH = $clog2(ROW_SIZE/WIN_SIZE);
localparam WIN_BEAT_NUM = WIN_SIZE / BEAT_SIZE;

logic                       cache_enable;
logic                       cache_wr_en;
logic [ADDR_WIDTH-1:0]      cache_wr_addr;
logic [ADDR_WIDTH-1:0]      cache_wr_addr_r;
logic [CACHE_WIDTH-1:0]     cache_din;
logic [CACHE_WIDTH-1:0]     wr_din;
logic signed [DATA_WIDTH-1:0]           cache_data_signed   [WIN_SIZE-1:0];

logic [WIN_BEAT_NUM-1:0]        win_pos;

logic [BEAT_SIZE*DATA_WIDTH-1:0] s_axis_tdata_r;
logic                            s_axis_tvalid_r;
logic                            s_axis_tready_r;
logic                            s_axis_tlast_r;

localparam S_IDLE   = 0;
localparam S_LOAD   = 1;
localparam S_WRITE  = 2;

logic [3:0] c_state;
logic [3:0] n_state;

always @(*) begin
    for (int i = 0; i < WIN_SIZE; i++)
        cache_data_signed[i] = cache_din[i*DATA_WIDTH+:DATA_WIDTH];
end

// Reg axi signals.
always @(posedge aclk) begin
    s_axis_tdata_r <= s_axis_tdata;
    s_axis_tvalid_r <= s_axis_tvalid;
    s_axis_tready_r <= s_axis_tready;
    s_axis_tlast_r <= s_axis_tlast;
end

// State machine.
always @(posedge aclk) begin
    if(~aresetn)
        c_state <= S_IDLE;
    else
        c_state <= n_state;
end
always @(*) begin
    case (c_state)
        S_IDLE: 
            if(s_axis_tvalid & s_axis_tready)
                n_state = S_LOAD;
            else
                n_state = S_IDLE;
        S_LOAD:
            if(s_axis_tvalid_r & s_axis_tready_r & s_axis_tlast_r)
                n_state = S_IDLE;
            else
                n_state = S_LOAD;
        default: n_state = S_IDLE;
    endcase
end

// Concatenate phases and send it into cache.
always @(posedge aclk) begin
    if(~aresetn)
        cache_din <= 0;
    else begin
        for (int i = 0; i < WIN_BEAT_NUM; i++) begin
            if(win_pos[i])
                cache_din[i*BEAT_WIDTH+:BEAT_WIDTH] <= s_axis_tdata_r;
        end
    end
end
always @(posedge aclk) begin
    if(~aresetn)
        win_pos <= 'b1;
    else if(c_state == S_LOAD)
        win_pos <= {win_pos[WIN_BEAT_NUM-2:0], win_pos[WIN_BEAT_NUM-1]};
    else
        win_pos <= 'b1;
end

// Calculate write address.
always @(posedge aclk) begin
    if(~aresetn)
        cache_wr_addr <= 0;
    else if(c_state == S_LOAD)
        if(win_pos[WIN_BEAT_NUM-1])
            cache_wr_addr <= cache_wr_addr + 1;
        else 
            cache_wr_addr <= cache_wr_addr;
    else
        cache_wr_addr <= 0;
    cache_wr_addr_r <= cache_wr_addr;
end

// Assign cache write enable signal.
always @(posedge aclk) begin
    if(~aresetn)
        cache_wr_en <= 0;
    else if(win_pos[WIN_BEAT_NUM-1])
        cache_wr_en <= 1;
    else
        cache_wr_en <= 0;
end

// Assign signals.
assign s_axis_tready = aresetn;
assign cache_enable = aresetn;

genvar i;
generate
for (i = 0; i < BEAT_SIZE; i=i+2) begin
    logic [ADDR_WIDTH-1:0] cache_addra;
    tdual_ram #(
        .ADDR_WIDTH_A       (   ADDR_WIDTH      ),
        .DATA_WIDTH_A       (   CACHE_WIDTH     ),
        .BYTE_WRITE_WIDTH_A (   CACHE_WIDTH     ),
        .ADDR_WIDTH_B       (   ADDR_WIDTH      ),
        .DATA_WIDTH_B       (   CACHE_WIDTH     ),
        .BYTE_WRITE_WIDTH_B (   CACHE_WIDTH     ),
        .READ_LATENCY_B     (   READ_LATENCY    )
    ) phase_cache_inst (
        .clk        (   aclk            ),
        .rst_n      (   aresetn         ),
        // A port.
        .enablea    (   cache_enable    ),
        .wr_ena     (   cache_wr_en     ),
        .dina       (   cache_din       ),
        .addra      (   cache_addra     ),
        .douta      (   cache_dout[i]   ),
        // B port.
        .enableb    (   cache_enable    ),
        .wr_enb     (   1'b0            ),
        .dinb       (   {CACHE_WIDTH{1'b0}}),
        .addrb      (   cache_addr[i+1] ),
        .doutb      (   cache_dout[i+1] )
    );
    // Switch ram poart a address signal.
    always @(posedge aclk) begin
        cache_addra <= (c_state == S_IDLE)? cache_addr[i] : cache_wr_addr_r;
    end
end
endgenerate

endmodule