`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/14/2022 01:39:10 PM
// Design Name: 
// Module Name: relPhaseTop
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module cal_rel_phase #(
    parameter BEAT_SIZE = 8,
    parameter DATA_WIDTH = 16,
    parameter BUFFER_DEPTH = 512
)(
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

localparam SHIF_STEPS = 4;
localparam BEAT_WIDTH = BEAT_SIZE*DATA_WIDTH;
localparam PIXEL_PART_WIDTH = BEAT_WIDTH/(DATA_WIDTH/8);

logic [SHIF_STEPS-1:0]                  pixel_buf_wr_en;
logic [SHIF_STEPS-1:0]                  pixel_buf_rd_en;
logic [BEAT_WIDTH:0]                    pixel_buf_din;
logic [SHIF_STEPS-1:0]                  pixel_buf_empty;
logic [SHIF_STEPS-1:0]                  pixel_buf_pfull;
logic [SHIF_STEPS-1:0][BEAT_WIDTH:0]    pixel_buf_dout;
logic                                   init_win;

logic [DATA_WIDTH-1:0]                  buf_rd_cnt;
logic                                   cal_vld_i;
logic [BEAT_SIZE-1:0]                   cal_vld;
logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   phase;
logic [BEAT_SIZE-1:0]                   tlast;
logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   mod_rate;
logic [SHIF_STEPS-1:0]                  buf_switch;
logic                                   cal_tlast_i;

logic                                   phase_buf_wr_en;
logic                                   phase_buf_rd_en;
logic [BEAT_WIDTH:0]                    phase_buf_din;
logic                                   phase_buf_pfull;
logic                                   phase_buf_empty;
logic [BEAT_WIDTH:0]                    phase_buf_dout;

genvar i;
generate;
for (i = 0; i < SHIF_STEPS; ++i) begin
    sync_fifo #(
        .FIFO_DEPTH         (  BUFFER_DEPTH/2       ),
        .PROG_FULL_THRESH   (  BUFFER_DEPTH/2-10    ),
        .DATA_WIDTH         (  BEAT_WIDTH+1         ),
        .READ_MODE          (  "fwft"               ),
        .READ_LATENCY       (   0                   )
    ) pixel_fifo (
        .clk    (   aclk    ),
        .rst_n  (   aresetn ),
    
        .wr_en  (   pixel_buf_wr_en[i]  ),
        .rd_en  (   pixel_buf_rd_en[i]  ),
        .din    (   pixel_buf_din       ),
        .dout   (   pixel_buf_dout[i]   ),

        .empty  (   pixel_buf_empty[i]  ),
        .pfull  (   pixel_buf_pfull[i]  )
    );
    assign pixel_buf_rd_en[i] = cal_vld_i & init_win;
    assign pixel_buf_din = {s_axis_tlast, s_axis_tdata};
end
endgenerate

always @(posedge aclk) begin
    if(~aresetn)
        buf_rd_cnt <= 0;
    else if(init_win)
        buf_rd_cnt <= 0;
    else if(cal_vld_i)
        buf_rd_cnt <= buf_rd_cnt + 1;
    else
        buf_rd_cnt <= buf_rd_cnt;
end

assign init_win = (buf_rd_cnt == DATA_WIDTH/8-1);

// Schedule pixel buffer.
always @(posedge aclk) begin
    if(~aresetn)
        buf_switch <= 4'b0001;
    else begin
        if(s_axis_tvalid & s_axis_tready & s_axis_tlast)
            buf_switch <= {buf_switch[2:0], buf_switch[3]};
    end
end

// Set axis slave signal.
always@(*) begin
    case (buf_switch)
        4'b0001: s_axis_tready = ~pixel_buf_pfull[0];
        4'b0010: s_axis_tready = ~pixel_buf_pfull[1];
        4'b0100: s_axis_tready = ~pixel_buf_pfull[2];
        4'b1000: s_axis_tready = ~pixel_buf_pfull[3];
        default: s_axis_tready = 1'b0;
    endcase
    for (int i = 0; i < SHIF_STEPS; ++i)
        pixel_buf_wr_en[i] = buf_switch[i] & s_axis_tvalid & s_axis_tready;
end

assign cal_vld_i = !pixel_buf_empty & ~phase_buf_pfull;
assign cal_tlast_i = pixel_buf_dout[0][BEAT_WIDTH] & init_win;

genvar j;
generate;
for (j = 0; j < BEAT_SIZE; ++j) begin
// Phase and modulate rate calculation.
    logic [DATA_WIDTH-1:0] phase_o;
    rel_phase_4steps #(
        .DATA_WIDTH (  DATA_WIDTH )
    ) rel_phase_4steps_inst (
        .clk        (   aclk            ),
        .rst_n      (   aresetn         ),
        .vld_i      (   cal_vld_i       ),
        .pixel1_i   (   pixel_buf_dout[0][buf_rd_cnt*PIXEL_PART_WIDTH+j*8+:8]),
        .pixel2_i   (   pixel_buf_dout[1][buf_rd_cnt*PIXEL_PART_WIDTH+j*8+:8]),
        .pixel3_i   (   pixel_buf_dout[2][buf_rd_cnt*PIXEL_PART_WIDTH+j*8+:8]),
        .pixel4_i   (   pixel_buf_dout[3][buf_rd_cnt*PIXEL_PART_WIDTH+j*8+:8]),
        .tlast_i    (   cal_tlast_i     ),
        .vld_o      (   cal_vld[j]      ),
        .tlast_o    (   tlast[j]        ),
        .phase_o    (   phase_o         ),
        .mod_rate_o (   mod_rate[j]     )
    );
    assign phase[j] = phase_o;
end
endgenerate

// Phase buffer
sync_fifo #(
    .FIFO_DEPTH         (  BUFFER_DEPTH     ),
    .PROG_FULL_THRESH   (  BUFFER_DEPTH-30  ),
    .DATA_WIDTH         (  BEAT_WIDTH+1     ),
    .READ_MODE          (  "fwft"           ),
    .READ_LATENCY       (   0               )
) phase_fifo (
    .clk    (   aclk    ),
    .rst_n  (   aresetn ),

    .wr_en  (   phase_buf_wr_en ),
    .rd_en  (   phase_buf_rd_en ),
    .din    (   phase_buf_din   ),
    .dout   (   phase_buf_dout  ),
    .pfull  (   phase_buf_pfull ),
    .empty  (   phase_buf_empty )
);
assign phase_buf_wr_en = cal_vld[0];
assign phase_buf_rd_en = m_axis_tready & m_axis_tvalid;
assign phase_buf_din = {tlast[0], phase};
assign m_axis_tdata = phase_buf_dout[BEAT_WIDTH-1:0];
assign m_axis_tvalid = ~phase_buf_empty;
assign m_axis_tlast = phase_buf_dout[BEAT_WIDTH];

endmodule
