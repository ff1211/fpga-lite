//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// match_core.sv
// 
// Description:
// Phase match core function core.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.16  ff          Initial version
//****************************************************************

`timescale 1ns/1ps

module match_core #(
    parameter ROW_SIZE = 1280,
    parameter WIN_SIZE = 128,
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16,
    parameter READ_LATENCY = 2,
    parameter MATCH_TH = 16'b00000000_10100000
) (
    input  logic                                    clk,
    input  logic                                    rst_n,

    input  logic [DATA_WIDTH*2:0]                   phase_buf_dout,
    input  logic                                    phase_buf_empty,
    output logic                                    phase_buf_rd_en,

    output logic [$clog2(ROW_SIZE/WIN_SIZE)-1:0]    cache_addr,
    input  logic [WIN_SIZE-1:0][DATA_WIDTH-1:0]     cache_data,

    output logic                                    vld_o,
    output logic                                    not_found,
    output logic signed [DATA_WIDTH-1:0]            y_sub_y1, 
    output logic signed [DATA_WIDTH-1:0]            y_sub_y0, 
    output logic signed [DATA_WIDTH-1:0]            x0, 
    output logic signed [DATA_WIDTH-1:0]            abs_phase1_pos_o,
    output logic                                    tlast_o
);

localparam FIRST_ADDR = 0;
localparam LAST_ADDR = ROW_SIZE/WIN_SIZE-1;

localparam S_IDLE   = 0;
localparam S_PIPE   = 1;
localparam S_STALL  = 2;
localparam S_REPIPE = 3;

localparam A_INSIDE_PRE_M   = 0;
localparam A_INSIDE_POST_L  = 1;
localparam A_INSIDE         = 2;
localparam A_MAY_SMALLER    = 3;
localparam A_MAY_LARGER     = 4;
localparam A_NOT_FOUND      = 5;

localparam PIPLINE_STAGES   = 2;

logic signed [DATA_WIDTH-1:0]   abs_phase1;
logic signed [DATA_WIDTH-1:0]   abs_phase1_pos;
logic                           abs_phase1_tlast;
logic signed [DATA_WIDTH-1:0]   abs_phase1_r;
logic signed [DATA_WIDTH-1:0]   abs_phase1_pos_r;
logic                           abs_phase1_tlast_r;
logic        [DATA_WIDTH*2:0]   shift_reg_din;
logic                           shift_reg_en;
logic        [DATA_WIDTH*2:0]   phase_buf_dout_r;
logic        [DATA_WIDTH*2:0]   phase_buf_dout_sr;
logic signed [DATA_WIDTH-1:0]   cache_data_signed   [WIN_SIZE-1:0];
logic        [3:0]              cache_rd_cnt;
logic                           stall;
logic                           repipe_done;
logic        [DATA_WIDTH-1:0]   repipe_cnt;
logic                           piping;
logic                           piping_r0;
logic                           piping_r1;
logic                           not_found_i;

logic                           search_vld_i;
logic signed [DATA_WIDTH-1:0]   search_error_i      [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]   search_error_i_sr   [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]   search_pos_i        [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]   win_error_m;
logic signed [DATA_WIDTH-1:0]   win_error_l;
logic signed [DATA_WIDTH-1:0]   win_error           [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]   win_pos             [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]   pre_win_m;
logic signed [DATA_WIDTH-1:0]   post_win_l;
logic signed [DATA_WIDTH-1:0]   pre_win_error_m;
logic signed [DATA_WIDTH-1:0]   post_win_error_l;
logic signed [DATA_WIDTH-1:0]   pre_win_pos_m;
logic signed [DATA_WIDTH-1:0]   post_win_pos_l;
logic                           pre_win_m_vld;
logic                           post_win_l_vld;
logic        [3:0]              analyze_result;

logic        [DATA_WIDTH-1:0]   c_state;
logic        [DATA_WIDTH-1:0]   n_state;

// phase_buf_dout[2*DATA_WIDTH]                -> tlast
// phase_buf_dout[2*DATA_WIDTH-1:DATA_WIDTH]   -> position
// phase_buf_dout[DATA_WIDTH-1:0]              -> phase

// State machine
always @(posedge clk) begin
    if(~rst_n)
        c_state <= S_IDLE;
    else
        c_state <= n_state;
end
always @(*) begin
    case (c_state)
        S_IDLE:
            if(~phase_buf_empty)
                n_state = S_PIPE;
            else
                n_state = S_IDLE;
        S_PIPE:
            if(stall)
                n_state = S_STALL;
            else if(phase_buf_empty)
                n_state = S_IDLE;
            else
                n_state = S_PIPE;
        S_STALL:
            if(cache_rd_cnt == READ_LATENCY)
                n_state = S_REPIPE;
            else
                n_state = S_STALL;
        S_REPIPE:
            if(stall)
                n_state = S_STALL;
            else if(repipe_done)
                n_state = S_PIPE;
            else
                n_state = S_REPIPE;
        default: n_state = S_IDLE;
    endcase
end
assign piping = ((c_state == S_PIPE) & (~phase_buf_empty)) | (c_state == S_REPIPE);

assign phase_buf_rd_en = (c_state == S_PIPE) & (~phase_buf_empty);
shift_reg #(
    .DATA_WIDTH (   DATA_WIDTH*2+1  ),
    .STAGES     (   PIPLINE_STAGES  )
) in_reg_inst (
    .clk        (   clk                 ),
    .en         (   shift_reg_en        ),
    .din        (   shift_reg_din       ),
    .dout       (   phase_buf_dout_sr  )
);
assign shift_reg_en = piping;
assign shift_reg_din = {abs_phase1_tlast, abs_phase1_pos, abs_phase1};

// Select pipeline input according to the state.
always @(*) begin
    if(c_state == S_PIPE) begin
        abs_phase1 = phase_buf_dout[DATA_WIDTH-1:0];
        abs_phase1_pos = phase_buf_dout[2*DATA_WIDTH-1:DATA_WIDTH];
        abs_phase1_tlast = phase_buf_dout[2*DATA_WIDTH];
    end else begin
        abs_phase1 = phase_buf_dout_sr[DATA_WIDTH-1:0];
        abs_phase1_pos = phase_buf_dout_sr[2*DATA_WIDTH-1:DATA_WIDTH];
        abs_phase1_tlast = phase_buf_dout_sr[2*DATA_WIDTH];
    end
end

always @(posedge clk) begin
    if(~rst_n)
        repipe_cnt <= 0;
    else if(c_state == S_REPIPE)
        repipe_cnt <= repipe_cnt + 1;
    else
        repipe_cnt <= 0;
end
assign repipe_done = (repipe_cnt == (PIPLINE_STAGES - 1));

// Turn cache data out to signed separate array.
always @(*) begin
    for (int i = 0; i < WIN_SIZE; i++)
        cache_data_signed[i] = cache_data[i];
end

// Substract and get error.
// Get output error.
always @(posedge clk) begin
    for (int i = 0; i < WIN_SIZE; i++) begin
        win_error[i] <= abs_phase1 - cache_data_signed[i];
        win_pos[i] <= i + cache_addr*WIN_SIZE;
    end
    pre_win_error_m <= abs_phase1 - pre_win_m;
    post_win_error_l <= abs_phase1 - post_win_l;
end
// assign win_error_m = post_win_l_vld? post_win_error_l : win_error[WIN_SIZE-1];
// assign win_error_l = pre_win_m_vld? pre_win_error_m : win_error[0];
assign win_error_m = win_error[WIN_SIZE-1];
assign win_error_l = win_error[0];

always @(posedge clk) begin
    piping_r0 <= piping;
    piping_r1 <= piping_r0;
    abs_phase1_r <= abs_phase1;
    abs_phase1_pos_r <= abs_phase1_pos;
    abs_phase1_tlast_r <= abs_phase1_tlast;
end
assign error_cal_vld = piping_r0;

always @(*) begin
    case ({win_error_m[DATA_WIDTH-1], win_error_l[DATA_WIDTH-1]})
        // >= msb, >= lsb
        2'b00: analyze_result = (post_win_l_vld & post_win_error_l[DATA_WIDTH-1])? A_INSIDE_POST_L : (cache_addr == LAST_ADDR)? A_NOT_FOUND : A_MAY_LARGER;
        // >= msb, < lsb, impossible
        2'b01: analyze_result = (post_win_l_vld & post_win_error_l[DATA_WIDTH-1])? A_INSIDE_POST_L : (cache_addr == LAST_ADDR)? A_NOT_FOUND : A_MAY_LARGER;
        // < msb, >= lsb
        2'b10: analyze_result = A_INSIDE;
        // < msb, < lsb
        2'b11: analyze_result = (pre_win_m_vld & ~pre_win_error_m[DATA_WIDTH-1])? A_INSIDE_PRE_M : (cache_addr == FIRST_ADDR)? A_NOT_FOUND : A_MAY_SMALLER;
        default: analyze_result = A_NOT_FOUND;
    endcase
end
assign stall = error_cal_vld & ((analyze_result == A_MAY_SMALLER) | (analyze_result == A_MAY_LARGER));

always @(*) begin
    search_error_i = win_error;
    search_pos_i = win_pos;
    if(analyze_result == A_INSIDE) begin
        search_error_i = win_error;
        search_pos_i = win_pos;
    end else if(analyze_result == A_INSIDE_POST_L) begin
        search_error_i = {post_win_error_l, win_error[WIN_SIZE-1:1]};
        search_pos_i = {post_win_pos_l, win_pos[WIN_SIZE-1:1]};
    end else if(analyze_result == A_INSIDE_PRE_M) begin
        search_error_i = {win_error[WIN_SIZE-2:0], pre_win_error_m};
        search_pos_i = {win_pos[WIN_SIZE-2:0], pre_win_pos_m};
    end else begin
        search_error_i = win_error;
        search_pos_i = win_pos;
    end
end
assign search_vld_i = ~stall & error_cal_vld;
assign not_found_i = (analyze_result == A_NOT_FOUND);

// Change cache address.
always @(posedge clk) begin
    if(~rst_n)
        cache_addr <= 0;
    else if((c_state != S_STALL) & (n_state == S_STALL)) begin
        case (analyze_result)
            A_MAY_SMALLER: cache_addr <= cache_addr - 1;
            A_MAY_LARGER: cache_addr <= cache_addr + 1;
            default: cache_addr <= cache_addr;
        endcase
    end
end
// Wait cache read result.
always @(posedge clk) begin
    if(~rst_n)
        cache_rd_cnt <= 0;
    else if(c_state == S_STALL)
        cache_rd_cnt <= cache_rd_cnt + 1;
    else
        cache_rd_cnt <= 0;
end
always @(posedge clk) begin
    if(~rst_n) begin
        pre_win_m_vld <= 0;
        post_win_l_vld <= 0;
    end else begin
        if(c_state != S_STALL & n_state == S_STALL)
            if(analyze_result == A_MAY_LARGER) begin
                pre_win_m <= cache_data_signed[WIN_SIZE-1];
                pre_win_pos_m <= cache_addr * WIN_SIZE - 1;
                pre_win_m_vld <= 1;
                post_win_l_vld <= 0;
            end else if(analyze_result == A_MAY_SMALLER) begin
                post_win_l <= cache_data_signed[0];
                post_win_pos_l <= (cache_addr + 1) * WIN_SIZE;
                post_win_l_vld <= 1;
                pre_win_m_vld <= 0;
            end else begin
                pre_win_m_vld <= pre_win_m_vld;
                post_win_l_vld <= post_win_l_vld;
            end
        else begin
            pre_win_m_vld <= pre_win_m_vld;
            post_win_l_vld <= post_win_l_vld;
        end
    end
end

search_core #(
    .DATA_WIDTH (   DATA_WIDTH  ),
    .WIN_SIZE   (   WIN_SIZE    )
) search_core_inst (
    .clk                (   clk                 ),
    .rst_n              (   rst_n               ),
    .error_i            (   search_error_i      ),
    .pos_i              (   search_pos_i        ),
    .abs_phase1_pos_i   (   abs_phase1_pos_r    ),
    .not_found_i        (   not_found_i         ),
    .vld_i              (   search_vld_i        ),
    .tlast_i            (   abs_phase1_tlast_r  ),

    .x0                 (   x0                  ),
    .y_sub_y0           (   y_sub_y0            ),
    .y_sub_y1           (   y_sub_y1            ),
    .abs_phase1_pos_o   (   abs_phase1_pos_o    ),
    .not_found_o        (   not_found           ),
    .tlast_o            (   tlast_o             ),
    .vld_o              (   vld_o               )
);
endmodule