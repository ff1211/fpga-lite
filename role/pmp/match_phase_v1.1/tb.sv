`timescale 1ns / 1ps

module tb (
);
logic clk;
logic rst_n;

parameter ROW_SIZE = 1280;
parameter WIN_SIZE = 32;
parameter BEAT_SIZE = 8;
parameter DATA_WIDTH = 16;
parameter BUFFER_DEPTH = 512;
parameter READ_LATENCY = 2;
parameter MATCH_TH = 16'b00000000_10100000;
localparam BEAT_WIDTH = BEAT_SIZE * DATA_WIDTH;
localparam CACHE_WIDTH = WIN_SIZE * DATA_WIDTH;
localparam ADDR_WIDTH = $clog2(ROW_SIZE/WIN_SIZE);
localparam WIN_BEAT_NUM = WIN_SIZE / BEAT_SIZE;

initial begin
    clk <= 0;
    rst_n <= 0;
    #200
    @(posedge clk) rst_n <= 1;
end

always #2 clk <= ~clk;

logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   s_axis_tdata;
logic                                   s_axis_tvalid;
logic                                   s_axis_tready;
logic                                   s_axis_tlast;

logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]   m_axis_tdata;
logic                                   m_axis_tvalid;
logic                                   m_axis_tready;
logic                                   m_axis_tlast;

assign m_axis_tready = 1;

match_phase #(
    .ROW_SIZE       (   ROW_SIZE        ),
    .WIN_SIZE       (   WIN_SIZE        ),
    .BEAT_SIZE      (   BEAT_SIZE       ),
    .DATA_WIDTH     (   DATA_WIDTH      ),
    .BUFFER_DEPTH   (   BUFFER_DEPTH    ),
    .READ_LATENCY   (   READ_LATENCY    ),
    .MATCH_TH       (   MATCH_TH        )
) phase_match_inst (
    .aclk           (   clk     ),
    .aresetn        (   rst_n   ),

    .s_axis_tdata   (   s_axis_tdata    ),
    .s_axis_tvalid  (   s_axis_tvalid   ),
    .s_axis_tready  (   s_axis_tready   ),
    .s_axis_tlast   (   s_axis_tlast    ),
    
    .m_axis_tdata   (   m_axis_tdata    ),
    .m_axis_tvalid  (   m_axis_tvalid   ),
    .m_axis_tready  (   m_axis_tready   ),
    .m_axis_tlast   (   m_axis_tlast    )
);

parameter PACKAGE_LEN = 160;
initial begin
    s_axis_tvalid <= 0;
    s_axis_tlast <= 0;
    wait(rst_n);
    for (int i  = 0; i <= PACKAGE_LEN; ++i) begin
        @(posedge clk) begin
            if(i < PACKAGE_LEN) begin
                for (int j = 0; j < BEAT_SIZE; j++) begin
                    s_axis_tdata[j] <= 16'b00000000_00000100 * (i*BEAT_SIZE+j);
                end
                s_axis_tvalid <= 1;
                s_axis_tlast <= (i == PACKAGE_LEN-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
    #100
    for (int i  = 0; i <= PACKAGE_LEN; ++i) begin
        @(posedge clk) begin
            if(i < PACKAGE_LEN) begin
                for (int j = 0; j < BEAT_SIZE; j++) begin
                    s_axis_tdata[j] <= 16'b00000000_00000100 * (i*BEAT_SIZE+j) + 16'b00000000_00100000;
                end
                s_axis_tvalid <= 1;
                s_axis_tlast <= (i == PACKAGE_LEN-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
end


// logic ram_wr_en;
// logic [ADDR_WIDTH-1:0] ram_addr;
// initial begin
//     ram_wr_en <= 0;
//     ram_addr <= 1;
//     wait(rst_n);
//     #100
//     @(posedge clk) ram_wr_en <= 1;
//     @(posedge clk) ram_wr_en <= 0;
//     #100
//     @(posedge clk)
//         ram_addr <= 0;
// end
endmodule