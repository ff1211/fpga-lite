//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// control.sv
// 
// Description:
// Schedule phases and send them to match tree and get result.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.22  ff          Initial version
//****************************************************************

module control #(
    parameter ROW_SIZE = 1280,
    parameter WIN_SIZE = 128,
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16,
    parameter BUFFER_DEPTH = 512
) (
    input  logic                            clk,
    input  logic                            rst_n,

    input  logic [BEAT_SIZE*DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                            s_axis_tvalid,
    output logic                            s_axis_tready,
    input  logic                            s_axis_tlast,

    output logic [BEAT_SIZE*DATA_WIDTH-1:0] m_cache_axis_tdata,
    output logic                            m_cache_axis_tvalid,
    input  logic                            m_cache_axis_tready,
    output logic                            m_cache_axis_tlast,

    output logic                            phase_buf_wr_en,
    output logic                            phase_buf_rd_en,
    output logic [BEAT_SIZE*DATA_WIDTH:0]   phase_buf_din,
    input  logic                            phase_buf_empty,
    input  logic                            phase_buf_pfull,
    input  logic [BEAT_SIZE*DATA_WIDTH:0]   phase_buf_dout,

    output logic signed [DATA_WIDTH-1:0]    abs_phase1      [BEAT_SIZE-1:0],
    output logic signed [DATA_WIDTH-1:0]    abs_phase1_pos  [BEAT_SIZE-1:0],
    output logic                            vld_o,

    input  logic signed [DATA_WIDTH-1:0]    disparity       [BEAT_SIZE-1:0],
    input  logic [BEAT_SIZE-1:0]            vld_i,

    output logic [BEAT_SIZE*DATA_WIDTH-1:0] m_axis_tdata,
    output logic                            m_axis_tvalid,
    input  logic                            m_axis_tready,
    output logic                            m_axis_tlast
);

localparam S_IDLE           = 0;
localparam S_READ_PHASE     = 1;
localparam S_WAIT_RESULT    = 2;
localparam S_SEND_AXIS      = 3;

logic [1:0]                             axis_switch;
logic [3:0]                             c_state;
logic [3:0]                             n_state;
logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   disparity_r;
logic [BEAT_SIZE-1:0]                   disparity_vld;
logic [BEAT_SIZE*DATA_WIDTH:0]          phase_beat_r;
logic [$clog2(ROW_SIZE/BEAT_SIZE)-1:0]  phase_beats_shift;


// Axis switch. Load phase2 to cache and load phase1 to fifo.
always @(posedge clk) begin
    if(~rst_n)
        axis_switch <= 2'b01;
    else begin
        if(s_axis_tvalid & s_axis_tready & s_axis_tlast)
            axis_switch <= {axis_switch[0], axis_switch[1]};
    end
end

assign m_cache_axis_tdata   = s_axis_tdata;
assign m_cache_axis_tvalid  = axis_switch[0]? s_axis_tvalid : 0;
assign m_cache_axis_tlast   = s_axis_tlast;

assign s_axis_tready        = axis_switch[0]? m_cache_axis_tready : ~phase_buf_pfull & rst_n;

assign phase_buf_din        = {s_axis_tlast, s_axis_tdata};
assign phase_buf_wr_en      = axis_switch[0]? 0 : s_axis_tvalid & s_axis_tready;

// State machine.
always @(*) begin
    case (c_state)
        S_IDLE:
            if(~phase_buf_empty)
                n_state = S_READ_PHASE;
            else
                n_state = S_IDLE;
        S_READ_PHASE:
            n_state = S_WAIT_RESULT;
        S_WAIT_RESULT:
            if(disparity_vld == {BEAT_SIZE{1'b1}})
                n_state = S_SEND_AXIS;
            else
                n_state = S_WAIT_RESULT;
        S_SEND_AXIS:
            if(m_axis_tready & m_axis_tvalid)
                n_state = S_IDLE;
            else
                n_state = S_SEND_AXIS;
        default: n_state = S_IDLE;
    endcase
end
always @(posedge clk) begin
    if(~rst_n)
        c_state <= S_IDLE;
    else
        c_state <= n_state;
end

// Read a beat of phase1 and calculate position.
always @(posedge clk) begin
    if(~rst_n)
        phase_buf_rd_en <= 0;
    else if((c_state == S_IDLE) & (n_state == S_READ_PHASE))
        phase_buf_rd_en <= 1;
    else
        phase_buf_rd_en <= 0;
end
always @(posedge clk) begin
    if((c_state == S_IDLE) & (n_state == S_READ_PHASE))
        phase_beat_r <= phase_buf_dout[BEAT_SIZE*DATA_WIDTH-1:0];
    else
        phase_beat_r <= phase_beat_r;
end

// Send phase1 and positions to match core.
always @(posedge clk) begin
    if(c_state == S_READ_PHASE)
        for (int i = 0; i < BEAT_SIZE; i++)
            abs_phase1[i] <= phase_beat_r[i*DATA_WIDTH+:DATA_WIDTH];
    else
        abs_phase1 <= abs_phase1;
end
always @(posedge clk) begin
    if(~rst_n)
        phase_beats_shift <= 0;
    else if((c_state == S_SEND_AXIS) & (n_state == S_IDLE))
        phase_beats_shift <= phase_beats_shift + 1;
    else
        phase_beats_shift <= phase_beats_shift;
end
always @(posedge clk) begin
    for (int i = 0; i < BEAT_SIZE; i++)
        if(c_state == S_READ_PHASE)
            abs_phase1_pos[i] <= phase_beats_shift*BEAT_SIZE + i;
        else
            abs_phase1_pos[i] <= abs_phase1_pos[i];
end
always @(posedge clk) begin
    if(~rst_n)
        vld_o <= 0;
    else if(c_state == S_READ_PHASE)
        vld_o <= 1;
    else
        vld_o <= 0;
end

// Wait match core send back result.
always @(posedge clk) begin
    if(~rst_n)
        disparity_vld <= 0;
    else if(c_state == S_WAIT_RESULT)
        for (int i = 0; i < BEAT_SIZE; i++)
            if(vld_i[i])
                disparity_vld[i] <= 1;
            else
                disparity_vld[i] <= disparity_vld[i];
    else
        disparity_vld <= 0;
end
always @(posedge clk) begin
    if(c_state == S_WAIT_RESULT)
        for (int i = 0; i < BEAT_SIZE; i++)
            if(vld_i[i])
                disparity_r[i] <= disparity[i];
            else
                disparity_r[i] <= disparity_r[i];
    else
        disparity_r <= disparity_r;
end

// Send disparity to axi stream.
assign m_axis_tvalid = (c_state == S_SEND_AXIS);
assign m_axis_tdata = disparity_r;
assign m_axis_tlast = (phase_beats_shift == ROW_SIZE/BEAT_SIZE - 1);

endmodule