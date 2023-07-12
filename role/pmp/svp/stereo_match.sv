//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// stereo_match.sv
// 
// Description:
// Phase match core function core.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2023.03.16  ff          Initial version
//****************************************************************

`timescale 1ns/1ps

module stereo_match #(
    parameter COLS = 1280,
    parameter MAX_DIS = 128,
    parameter BEAT_SIZE = 8,
    parameter ISSUE_WIDTH = 4,
    parameter DATA_WIDTH = 16,
    parameter MATCH_TH = 16'b00000000_10100000
) (
    input  logic                                        clk,
    input  logic                                        rst_n,

    input  logic [MAX_DIS*DATA_WIDTH-1:0]               lp_buf_dout,
    input  logic                                        lp_buf_empty,
    output logic                                        lp_buf_rd_en,

    input  logic [BEAT_SIZE*DATA_WIDTH:0]               rp_buf_dout,
    input  logic                                        rp_buf_empty,
    output logic                                        rp_buf_rd_en,
    output logic signed [DATA_WIDTH-1:0]                compare_val [ISSUE_WIDTH-1:0],
    output logic [ISSUE_WIDTH-1:0][(DATA_WIDTH+1)*3-1:0]user_val,
    output logic [ISSUE_WIDTH-1:0]                      vld
);

localparam FAN_OUT = 32;
localparam BEAT_WIDTH = BEAT_SIZE * DATA_WIDTH;
localparam BEAT_NUM = COLS / BEAT_SIZE;
localparam MAX_DIS_BEATS = MAX_DIS / BEAT_SIZE;
// Define how many compare lines in the core.
// 1, 2, 4, 8.

localparam MATCHES_PER_BEAT = BEAT_SIZE / ISSUE_WIDTH;
localparam MATCH_TIMES = MAX_DIS / ISSUE_WIDTH;

// State machine define.
localparam S_IDLE       = 0;
localparam S_PREFILL    = 1;
localparam S_LOAD_LP    = 2;
localparam S_MATCH      = 3;

logic [1:0]                             c_state;
logic [1:0]                             n_state;
logic [MAX_DIS-1:0][DATA_WIDTH-1:0]     lp_buf_dout_p;
logic signed [DATA_WIDTH-1:0]           lp_buf_dout_s       [MAX_DIS-1:0];
logic signed [DATA_WIDTH-1:0]           lp_buf_dout_shift   [2*MAX_DIS-1:0];
logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   rp_buf_dout_p;
logic signed [DATA_WIDTH-1:0]           rp_buf_dout_s       [BEAT_SIZE-1:0];
// Make 8 copies to reduce fan out.
logic signed [DATA_WIDTH-1:0]           rp_buf_dout_fan     [FAN_OUT-1:0][BEAT_SIZE-1:0];

// Count how many beats of phases have been matched.
logic [DATA_WIDTH-1:0]  rp_beat_cnt;
// Count how many matches have been conducted.
logic [DATA_WIDTH-1:0]  cur_match_cnt;
// Indicate to read a new beat of left phase.
// It will be valid every time the core has matched 15 beats of phase before having matched 144 beats.
logic to_read_new_lp;
// Indicate the matching of current row is almost complete, with only one beat to be matched.
logic almost_complete;
logic prefill_cnt;

// State machine.
always @(posedge clk) begin
    if(~rst_n)
        c_state <= S_IDLE;
    else
        c_state <= n_state;
end
always @(*) begin
    case (c_state)
        S_IDLE:
            if(~rp_buf_empty & ~lp_buf_empty)
                n_state = S_PREFILL;
            else
                n_state = S_IDLE;
        S_PREFILL:
            if((prefill_cnt == 1) & ~lp_buf_empty)
                n_state = S_MATCH;
            else
                n_state = S_PREFILL;
        S_LOAD_LP:
            if(~lp_buf_empty)
                n_state = S_MATCH;
            else
                n_state = S_LOAD_LP;
        S_MATCH:
            if(almost_complete)
                n_state = S_IDLE;
            else if(to_read_new_lp)
                n_state = S_LOAD_LP;
            else
                n_state = S_MATCH;

        default: n_state = S_IDLE;
    endcase
end

// Prefill state.
always @(posedge clk) begin
    if(~rst_n)
        prefill_cnt <= 0;
    else if (c_state == S_PREFILL)
        if (lp_buf_rd_en)
            prefill_cnt <= prefill_cnt + 1;
        else
            prefill_cnt <= prefill_cnt;
    else
        prefill_cnt <= 0;
end

// Left phase shift register.
always @(posedge clk) begin
    if(c_state == S_PREFILL)
        if(prefill_cnt == 0)
            lp_buf_dout_shift[MAX_DIS-1:0] <= lp_buf_dout_s;
        else
            lp_buf_dout_shift[2*MAX_DIS-1:MAX_DIS] <= lp_buf_dout_s;
    else if(c_state == S_LOAD_LP)
        lp_buf_dout_shift[2*MAX_DIS-1:MAX_DIS] <= lp_buf_dout_s;
    else if(c_state == S_MATCH)
        for (int i = 0; i < MAX_DIS*2; i++)
            if(i < MAX_DIS*2-ISSUE_WIDTH)
                lp_buf_dout_shift[i] <= lp_buf_dout_shift[i+ISSUE_WIDTH];
            else
                lp_buf_dout_shift[i] <= 0;
    else
        lp_buf_dout_shift <= lp_buf_dout_shift;
end

// Left phase buffer control.
assign lp_buf_rd_en = ((c_state == S_PREFILL) | (c_state == S_LOAD_LP)) & ~lp_buf_empty;
always @(*) begin
    for (int i = 0; i < MAX_DIS; i++) begin
        lp_buf_dout_p[i] = lp_buf_dout[i*DATA_WIDTH+:DATA_WIDTH];
        lp_buf_dout_s[i] = lp_buf_dout_p[i];
    end
end

// Right phase buffer control.
// Because the right phases are sent in first, the right phase buffer wonts be empty during the matching.
// Which means it is not necessary to check the empty signal of fifo.
always @(*) begin
    if(c_state == S_MATCH)
        rp_buf_rd_en = (cur_match_cnt == BEAT_SIZE / ISSUE_WIDTH - 1) & ~to_read_new_lp;
    else
        rp_buf_rd_en = (n_state == S_MATCH);
end
always @(*) begin
    for (int i = 0; i < BEAT_SIZE; i++) begin
        rp_buf_dout_p[i] = rp_buf_dout[DATA_WIDTH*i+:DATA_WIDTH];
        rp_buf_dout_s[i] = rp_buf_dout_p[i];
    end
end
always @(posedge clk) begin
    for (int i = 0; i < FAN_OUT; i++)
        for (int j = 0; j < BEAT_SIZE; j++)
            if(rp_buf_rd_en)
                rp_buf_dout_fan[i][j] <= rp_buf_dout_s[j];
end

// Phase count.
always @(posedge clk) begin
    if(~rst_n)
        cur_match_cnt <= 0;
    else if (cur_match_cnt == BEAT_SIZE / ISSUE_WIDTH - 1)
        cur_match_cnt <= 0;
    else if (c_state == S_MATCH)
        cur_match_cnt <= cur_match_cnt + 1;
    else
        cur_match_cnt <= cur_match_cnt;
end

// Beat count.
always @(posedge clk) begin
    if(~rst_n)
        rp_beat_cnt <= 0;
    else if (n_state == S_IDLE)
        rp_beat_cnt <= 0;
    else if (rp_buf_rd_en)
        rp_beat_cnt <= rp_beat_cnt + 1;
    else
        rp_beat_cnt <= rp_beat_cnt;
end
// Need read left phase COLS / MAX_DIS times when come into match state, as the first group of left phase has been read when IDLE to READ state.
// Reading COLS / MAX_DIS times is to read the last entry with content 0 out.
always @(*) begin
    to_read_new_lp = 0;
    for (int i = 1; i < COLS / MAX_DIS; i++) 
        if((rp_beat_cnt == i * MAX_DIS / BEAT_SIZE) & (cur_match_cnt == BEAT_SIZE / ISSUE_WIDTH - 1))
            to_read_new_lp = 1;
end
assign almost_complete = (rp_beat_cnt == COLS / BEAT_SIZE) & (cur_match_cnt == BEAT_SIZE / ISSUE_WIDTH - 1);

genvar i, j;
generate
// Generate compare tree.
for (i = 0; i < ISSUE_WIDTH; i++) begin
    // Phase deviation from left to right. 
    logic signed [DATA_WIDTH-1:0] compare_val_i [MAX_DIS-1:0];

    // match_infor[DATA_WIDTH:0]                  {vld, phase deviation to previous pixel's phase}
    // match_infor[2*DATA_WIDTH+1:DATA_WIDTH+1]   {vld, phase deviation to latter pixel's phase}
    // match_infor[3*DATA_WIDTH+2:2*DATA_WIDTH+2] {vld, disparity}
    logic [MAX_DIS-1:0][(DATA_WIDTH+1)*3-1:0]   user_val_i;
    logic                                       vld_i;

    logic signed [DATA_WIDTH-1:0]               compare_val_o;
    logic        [(DATA_WIDTH+1)*3-1:0]         user_val_o;
    logic                                       vld_o;

    compare_tree #(
        .DEPTH      (   $clog2(MAX_DIS) ),
        .USER_WIDTH (   (DATA_WIDTH+1)*3),
        .DATA_WIDTH (   DATA_WIDTH      ),
        .TYPE       (   "min"           )
    ) compare_tree_inst (
        .clk            (   clk             ),
        .rst_n          (   rst_n           ),

        .compare_val_i  (   compare_val_i   ),
        .user_val_i     (   user_val_i      ),
        .vld_i          (   vld_i           ),

        .compare_val_o  (   compare_val_o   ),
        .user_val_o     (   user_val_o      ),
        .vld_o          (   vld_o           )
    );
    // Substract left phase from right phase.
    for (j = 0; j < FAN_OUT; j++) begin
        always @(posedge clk) begin
            for (int jj = 0; jj < BEAT_SIZE / ISSUE_WIDTH; jj++)
                if(cur_match_cnt == jj)
                    for (int ii = 0; ii < MAX_DIS / FAN_OUT; ii++)
                        compare_val_i[j*MAX_DIS/FAN_OUT+ii] <= rp_buf_dout_fan[j][jj*ISSUE_WIDTH+i] - lp_buf_dout_shift[i+ii+j*MAX_DIS/FAN_OUT];
        end
    end

    for (j = 0; j < MAX_DIS; j++) begin
        assign user_val_i[j][DATA_WIDTH-1:0] = (j == 0)? 0 : compare_val_i[j-1];
        assign user_val_i[j][DATA_WIDTH*2-1:DATA_WIDTH] = (j == MAX_DIS-1)? 0 : compare_val_i[j+1];
        assign user_val_i[j][DATA_WIDTH*3-1:DATA_WIDTH*2] = j;
        assign user_val_i[j][DATA_WIDTH*3] = (j != 0);
        assign user_val_i[j][DATA_WIDTH*3+1] = (j != MAX_DIS-1);
        assign user_val_i[j][DATA_WIDTH*3+2] = 1;
    end

    always @(posedge clk) 
        vld_i = (c_state == S_MATCH);
    assign compare_val[i] = compare_val_o;
    assign user_val[i] = user_val_o;
    assign vld[i] = vld_o;
end
endgenerate
endmodule