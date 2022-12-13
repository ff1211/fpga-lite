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

    input  logic [DATA_WIDTH*2:0]                   phase_fifo_dout,
    input  logic                                    phase_fifo_empty,
    output logic                                    phase_fifo_rd_en,

    output logic [$clog2(ROW_SIZE/WIN_SIZE)-1:0]    cache_addr,
    input  logic [WIN_SIZE-1:0][DATA_WIDTH-1:0]     cache_data,
    output logic                                    result_vld,
    output logic [DATA_WIDTH-1:0]                   result
);

localparam S_IDLE   = 0;
localparam S_PIPE   = 1;
localparam S_STALL  = 2;
localparam S_REPIPE = 3;

localparam A_INSIDE         = 0;
localparam A_BACK_WIN       = 1;
localparam A_FORWARD_WIN    = 2;
localparam A_NOT_FOUND      = 3;

logic signed [DATA_WIDTH-1:0]   abs_phase1;
logic signed [DATA_WIDTH-1:0]   abs_phase1_pos;
logic                           abs_phase1_tlast;
logic        [DATA_WIDTH*2:0]   shift_reg_din;
logic        [DATA_WIDTH*2:0]   shift_reg_en;
logic        [DATA_WIDTH*2:0]   phase_fifo_dout_r;
logic        [DATA_WIDTH*2:0]   phase_fifo_dout_sr;
logic signed [DATA_WIDTH-1:0]   cache_data_signed   [WIN_SIZE-1:0];
logic        [3:0]              cache_rd_cnt;
logic                           stall;
logic                           repipe_done;
logic                           piping;

logic                           error_cal_vld;
logic                           tree_vld_i;
logic signed [DATA_WIDTH-1:0]   tree_error_i        [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]   tree_pos_i          [WIN_SIZE-1:0];
logic                           tree_vld_o;
logic signed [DATA_WIDTH-1:0]   tree_error_o;
logic signed [DATA_WIDTH-1:0]   tree_pos_o;
logic signed [DATA_WIDTH-1:0]   tree_error_m;
logic signed [DATA_WIDTH-1:0]   tree_error_l;
logic signed [DATA_WIDTH-1:0]   pre_win_m;
logic signed [DATA_WIDTH-1:0]   post_win_l;
logic                           pre_win_m_vld;
logic                           post_win_l_vld;
logic        [3:0]              analyze_result;
logic        [3:0]              analyze_result_sr;
logic        [3:0]              analyze_result_sr_d0;

logic        [DATA_WIDTH-1:0]   c_state;
logic        [DATA_WIDTH-1:0]   n_state;

// phase_fifo_dout[2*DATA_WIDTH]                -> tlast
// phase_fifo_dout[2*DATA_WIDTH-1:DATA_WIDTH]   -> position
// phase_fifo_dout[DATA_WIDTH-1:0]              -> phase

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
            if(~phase_fifo_empty)
                n_state = S_PIPE;
            else
                n_state = S_IDLE;
        S_PIPE:
            if(stall)
                n_state = S_STALL;
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
assign piping = (c_state == S_PIPE) | (c_state == S_REPIPE);

// Read phase.
always @(posedge clk) begin
    if(phase_fifo_rd_en)
        phase_fifo_dout_r <= phase_fifo_dout;
    else
        phase_fifo_dout_r <= phase_fifo_dout_r;
end
assign phase_fifo_rd_en = (c_state == S_PIPE);
shift_reg #(
    .DATA_WIDTH (   DATA_WIDTH*2+1  ),
    .STAGES     (   8               )
) in_reg_inst (
    .clk        (   clk                 ),
    .en         (   shift_reg_en        ),
    .din        (   shift_reg_din       ),
    .dout       (   phase_fifo_dout_sr  )
);
assign shift_reg_en = piping;
assign shift_reg_din = {abs_phase1_tlast, abs_phase1_pos, abs_phase1};

// Select pipeline input according to the state.
always @(*) begin
    if(c_state == S_PIPE) begin
        abs_phase1 = phase_fifo_dout_r[DATA_WIDTH-1:0];
        abs_phase1_pos = phase_fifo_dout_r[2*DATA_WIDTH-1:DATA_WIDTH];
        abs_phase1_tlast = phase_fifo_dout_r[2*DATA_WIDTH];
    end else begin
        abs_phase1 = phase_fifo_dout_sr[DATA_WIDTH-1:0];
        abs_phase1_pos = phase_fifo_dout_sr[2*DATA_WIDTH-1:DATA_WIDTH];
        abs_phase1_tlast = phase_fifo_dout_sr[2*DATA_WIDTH];
    end
end

// Turn cache data out to signed separate array.
always @(*) begin
    for (int i = 0; i < WIN_SIZE; i++)
        cache_data_signed[i] = cache_data[i*DATA_WIDTH+:DATA_WIDTH];
end

// Substract and get error.
always @(posedge clk) begin
    for (int i = 0; i < WIN_SIZE; i++) begin
        tree_error_i[i] <= abs_phase1 - cache_data_signed[i];
        tree_pos_i[i] <= i + cache_addr*WIN_SIZE;
    end
end
assign tree_error_m = tree_error_i[WIN_SIZE-1];
assign tree_error_l = tree_error_i[0];
always @(posedge clk) begin
    error_cal_vld <= piping;
    tree_vld_i <= error_cal_vld;
end

// Compare tree
compare_tree #(
    .N_IN_ONE   (   4                   ),
    .DEPTH      (   $clog2(WIN_SIZE)/2  ),
    .LEVEL      (   0                   ),
    .DATA_WIDTH (   DATA_WIDTH          )
) compare_tree_inst (
    .clk        (   clk             ),
    .rst_n      (   rst_n           ),
    .error_i    (   tree_error_i    ),
    .pos_i      (   tree_pos_i      ),
    .vld_i      (   tree_vld_i      ),

    .error_o    (   tree_error_o    ),
    .pos_o      (   tree_pos_o      ),
    .vld_o      (   tree_vld_o      ) 
);

// Analyze compare tree result.
always @(*) begin
    case ({tree_error_m[DATA_WIDTH-1], tree_error_l[DATA_WIDTH-1]})
        2'b00: analyze_result = (tree_error_m == 0)? A_MAY_INSIDE : (cache_addr == LAST_ADDR)? A_NOT_FOUND : A_MAY_LARGER;
        2'b01: analyze_result = (tree_error_m == 0)? A_MAY_INSIDE : (cache_addr == LAST_ADDR)? A_NOT_FOUND : A_MAY_LARGER;
        2'b10: analyze_result = A_MAY_INSIDE;
        2'b11: analyze_result = (cache_addr == FIRST_ADDR)? A_NOT_FOUND : A_MAY_SMALLER;
        default: analyze_result = A_NOT_FOUND;
    endcase
end
// Shift reg analyze result.
shift_reg #(
    .DATA_WIDTH (   DATA_WIDTH*2+1  ),
    .STAGES     (   8               )
) in_reg_inst (
    .clk        (   clk                 ),
    .en         (   1'b1                ),
    .din        (   analyze_result      ),
    .dout       (   analyze_result_sr   )
);
assign stall = tree_vld_o & ((analyze_result_sr == A_MAY_SMALLER) | (analyze_result_sr == A_MAY_LARGER));
// Delay analyze result for address change.
always @(posedge clk) begin
    analyze_result_sr_d0 <= analyze_result_sr;
end

// Change cache address.
always @(posedge clk) begin
    if(~rst_n)
        cache_addr <= 0;
    else if(c_state == S_STALL) begin
        case (analyze_result_sr_d0)
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
    else if(n_state != S_STALLN)
        cache_rd_cnt <= 0;
    else if(c_state == S_STALL)
        cache_rd_cnt <= cache_rd_cnt + 1;
    else
        cache_rd_cnt <= cache_rd_cnt;
end

always @(posedge clk) begin
    if(~rst_n) begin
        pre_win_m_vld <= 0;
        post_win_l_vld <= 0;
    end else begin
        if(c_state != S_STALL & n_state == S_STALL)
            if(analyze_result_sr == A_FORWARD_WIN) begin
                pre_win_m <= 
                pre_win_m_vld <= 1;
            end else if(analyze_result_sr == A_BACK_WIN) begin
                post_win_l
                post_win_l_vld <= 1;
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

// Output match result.
logic signed [DATA_WIDTH-1:0] x0;
logic signed [DATA_WIDTH-1:0] x1;
logic signed [DATA_WIDTH-1:0] y_sub_y0;
logic signed [DATA_WIDTH-1:0] y_sub_y1;
logic                         not_found;

always @(posedge clk) begin
    
end

endmodule