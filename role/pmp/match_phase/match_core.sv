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

    input  logic signed [DATA_WIDTH-1:0]            abs_phase1,
    input  logic signed [DATA_WIDTH-1:0]            abs_phase1_pos,
    input  logic                                    vld_i,

    output logic [$clog2(ROW_SIZE/WIN_SIZE)-1:0]    cache_addr,
    input  logic [WIN_SIZE-1:0][DATA_WIDTH-1:0]     cache_data,

    output logic [DATA_WIDTH-1:0]                   disparity,
    output logic                                    vld_o
);

logic signed [DATA_WIDTH-1:0]           tree_error_i        [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]           tree_pos_i          [WIN_SIZE-1:0];

logic signed [DATA_WIDTH-1:0]           tree_error_o;
logic signed [DATA_WIDTH-1:0]           tree_pos_o;
logic signed [DATA_WIDTH-1:0]           tree_error_o_r;
logic signed [DATA_WIDTH-1:0]           tree_pos_o_r;
logic signed [DATA_WIDTH-1:0]           tree_error_m;
logic signed [DATA_WIDTH-1:0]           tree_error_l;

logic signed [DATA_WIDTH-1:0]           abs_phase1_r;
logic signed [DATA_WIDTH-1:0]           abs_phase1_pos_r;
logic                                   not_found;
logic signed [DATA_WIDTH-1:0]           cache_data_signed   [WIN_SIZE-1:0];
logic signed [DATA_WIDTH-1:0]           boundary_error;
logic        [DATA_WIDTH-1:0]           analyze_result_l;

logic [3:0]                             cache_rd_cnt;

logic                                   tree_vld_i;
logic signed [DATA_WIDTH-1:0]           error_o;
logic signed [DATA_WIDTH-1:0]           pos_o;
logic                                   tree_vld_o;

logic [3:0]                             analyze_result;

logic [3:0]                             c_state;
logic [3:0]                             n_state;

localparam FIRST_ADDR = 0;
localparam LAST_ADDR = $clog2(ROW_SIZE/WIN_SIZE)-1;

localparam S_IDLE           = 0;
localparam S_CAL_ERROR      = 1;
localparam S_ANALYZE        = 2;
localparam S_MATCH          = 3;
localparam S_CAL_DISPARITY  = 4;
localparam S_CHANGE_WIN     = 5;

localparam A_MAY_SMALLER    = 0;
localparam A_MAY_INSIDE     = 1;
localparam A_MAY_LARGER     = 2;
localparam A_NOT_FOUND      = 3;

// Turn cache data out to signed separate array.
always @(*) begin
    for (int i = 0; i < WIN_SIZE; i++)
        cache_data_signed[i] = cache_data[i*DATA_WIDTH+:DATA_WIDTH];
end

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
            if(vld_i)
                n_state = S_CAL_ERROR;
            else 
                n_state = S_IDLE;
        S_CAL_ERROR:
            n_state = S_ANALYZE;

        S_ANALYZE:
            case (analyze_result)
                A_MAY_SMALLER:
                    if(analyze_result_l == A_MAY_LARGER)
                        n_state = S_CAL_DISPARITY;
                    else
                        n_state = S_CHANGE_WIN;
                A_MAY_INSIDE:
                    n_state = S_MATCH;
                A_MAY_LARGER:
                    if(analyze_result_l == A_MAY_SMALLER)
                        n_state = S_CAL_DISPARITY;
                    else
                        n_state = S_CHANGE_WIN;
                A_NOT_FOUND:
                    n_state = S_CAL_DISPARITY;
                default:
                    n_state = S_CAL_DISPARITY;
            endcase
        S_MATCH:
            if(tree_vld_o)
                n_state = S_CAL_DISPARITY;
            else
                n_state = S_MATCH;
        S_CAL_DISPARITY:
            n_state = S_IDLE;
        S_CHANGE_WIN:
            if(cache_rd_cnt == READ_LATENCY)
                n_state = S_ANALYZE;
            else
                n_state = S_CHANGE_WIN;
        default: n_state = S_IDLE;
    endcase
end

// Reg abs_phase1 and abs_phase1_pos when at idle state and input is valid.
always @(posedge clk) begin
    if(vld_i & (c_state == S_IDLE)) begin
        abs_phase1_r <= abs_phase1;
        abs_phase1_pos_r <= abs_phase1_pos;
    end
end
// Do substraction and get errors of this window.
always @(posedge clk) begin
    for(int i = 0; i < WIN_SIZE; i++) begin
        tree_error_i[i] <= abs_phase1_r - cache_data_signed[i];
        tree_pos_i[i] <= i + cache_addr*WIN_SIZE;
    end
end

// Analyze calculation result and change cache addr.
assign tree_error_m = tree_error_i[WIN_SIZE-1];
assign tree_error_l = tree_error_i[0];
always @(*) begin
    case ({tree_error_m[DATA_WIDTH-1], tree_error_l[DATA_WIDTH-1]})
        2'b00: analyze_result = (tree_error_m == 0)? A_MAY_INSIDE : (cache_addr == LAST_ADDR)? A_NOT_FOUND : A_MAY_LARGER;
        2'b01: analyze_result = (tree_error_m == 0)? A_MAY_INSIDE : (cache_addr == LAST_ADDR)? A_NOT_FOUND : A_MAY_LARGER;
        2'b10: analyze_result = A_MAY_INSIDE;
        2'b11: analyze_result = (cache_addr == FIRST_ADDR)? A_NOT_FOUND : A_MAY_SMALLER;
        default: analyze_result = A_NOT_FOUND;
    endcase
end
// Save boundary phase.
always @(posedge clk) begin
    if(c_state == S_ANALYZE) begin
        case (analyze_result)
            A_MAY_SMALLER: boundary_error <= tree_error_l;
            A_MAY_INSIDE: boundary_error <= boundary_error;
            A_MAY_LARGER: boundary_error <= tree_error_m;
            A_NOT_FOUND: boundary_error <= boundary_error;
            default: boundary_error <= boundary_error;
        endcase
    end
end
// Save analysis result.
always @(posedge clk) begin
    if(~rst_n)
        analyze_result_l <= A_NOT_FOUND;
    else if(c_state == S_ANALYZE)
        analyze_result_l <= analyze_result;
end
// Change cache address.
always @(posedge clk) begin
    if(~rst_n)
        cache_addr <= 0;
    else if(c_state == S_CHANGE_WIN) begin
        case (analyze_result)
            A_MAY_SMALLER: cache_addr <= cache_addr - 1;
            A_MAY_INSIDE: cache_addr <= cache_addr;
            A_MAY_LARGER: cache_addr <= cache_addr + 1;
            A_NOT_FOUND: cache_addr <= cache_addr;
            default: cache_addr <= cache_addr;
        endcase
    end
end

always @(posedge clk) begin
    if(~rst_n)
        not_found <= 0;
    else if((c_state == S_ANALYZE) & (analyze_result == A_NOT_FOUND))
        not_found <= 1;
    else
        not_found <= 0;
end

// Wait cache read result.
always @(posedge clk) begin
    if(~rst_n)
        cache_rd_cnt <= 0;
    else if(n_state != S_CHANGE_WIN)
        cache_rd_cnt <= 0;
    else if(c_state == S_CHANGE_WIN)
        cache_rd_cnt <= cache_rd_cnt + 1;
    else
        cache_rd_cnt <= cache_rd_cnt;
end

// Valid match tree input.
assign tree_vld_i = (c_state == S_ANALYZE) & (n_state == S_MATCH);

// Reg compare tree's output.
always @(posedge clk) begin
    tree_error_o_r <= tree_error_o[DATA_WIDTH-1]? -tree_error_o : tree_error_o;
    tree_pos_o_r <= tree_pos_o;
end

// Calculate disparity.
always @(posedge clk) begin
    if(not_found)
        disparity <= 0;
    else
        if(analyze_result == A_MAY_SMALLER)
            disparity <= boundary_error + tree_error_l
        else if(analyze_result == A_MAY_LARGER)
        if(tree_error_o_r < MATCH_TH)
            disparity <= abs_phase1_pos_r - tree_pos_o_r;
        else
            disparity <= 0;
end
always @(posedge clk) begin
    if(~rst_n)
        vld_o <= 0;
    else if(c_state == S_CAL_DISPARITY)
        vld_o <= 1;
    else
        vld_o <= 0;
end

compare_tree #(
    .DEPTH      (   $clog2(WIN_SIZE)    ),
    .LEVEL      (   0                   ),
    .DATA_WIDTH (   DATA_WIDTH          )
) compare_tree_inst(
    .clk        (   clk         ),
    .rst_n      (   rst_n       ),
    .error_i    (   tree_error_i),
    .pos_i      (   tree_pos_i  ),
    .vld_i      (   tree_vld_i  ),

    .error_o    (   tree_error_o),
    .pos_o      (   tree_pos_o  ),
    .vld_o      (   tree_vld_o  )
);

endmodule