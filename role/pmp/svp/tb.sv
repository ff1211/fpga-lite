`timescale 1ns / 1ps

module tb (
);

parameter COLS = 1280;
parameter BEAT_SIZE = 8;
parameter DATA_WIDTH = 16;
parameter MAX_DIS = 128;
parameter ISSUE_WIDTH = 2;
parameter BUFFER_DEPTH = 256;
parameter MATCH_TH = 16'b00000000_10100000;
localparam BEAT_WIDTH = BEAT_SIZE * DATA_WIDTH;

logic                   clk;
logic                   rst_n;
logic signed [15:0]     abs1[1279:0];
logic signed [15:0]     abs2[1279:0];
logic signed [15:0]     min[1279:0];

initial begin
    $readmemh("/home/ff/git/fpga-lite/role/pmp/svp/abs1_int_f.txt", abs1);
    $readmemh("/home/ff/git/fpga-lite/role/pmp/svp/abs2_int_f.txt", abs2);
end

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

svp #(
    .COLS           (   COLS            ),
    .MAX_DIS        (   MAX_DIS         ),
    .BEAT_SIZE      (   BEAT_SIZE       ),
    .DATA_WIDTH     (   DATA_WIDTH      ),
    .BUFFER_DEPTH   (   BUFFER_DEPTH    ),
    .ISSUE_WIDTH    (   ISSUE_WIDTH     ),
    .MATCH_TH       (   MATCH_TH        )
)svp_inst (
    .aclk           (   clk             ),
    .aresetn        (   rst_n           ),

    .s_axis_tdata   (   s_axis_tdata    ),
    .s_axis_tvalid  (   s_axis_tvalid   ),
    .s_axis_tready  (   s_axis_tready   ),
    .s_axis_tlast   (   s_axis_tlast    ),

    .m_axis_tdata   (),
    .m_axis_tvalid  (),
    .m_axis_tready  (),
    .m_axis_tlast   ()
);
int minn;
initial begin
    minn = abs2[116] - abs1[116];
    for (int i = 1; i < MAX_DIS; i++)
        if(abs(abs2[116] - abs1[116+i]) < abs(minn))
            minn = abs2[116] - abs1[116+i];
        else
            minn = minn;
end

initial begin
    for (int i = 0; i < COLS; i++) begin
        logic signed [DATA_WIDTH-1:0] min_temp;
        min_temp = abs2[i] - abs1[i];
        for (int j = 1; j < MAX_DIS; j++) begin
            logic signed [DATA_WIDTH-1:0] min_itr;
            if(i+j > COLS - 1)
                min_itr = abs2[i];
            else
                min_itr = abs2[i] - abs1[i+j];
            
            if(abs(min_itr) < abs(min_temp))
                min_temp = min_itr;
            else
                min_temp = min_temp;
        end
        min[i] = min_temp;
    end
end

parameter BEAT_LEN = 160;
initial begin
    s_axis_tvalid <= 0;
    s_axis_tlast <= 0;
    wait(rst_n);
    #200
    for (int i  = 0; i <= BEAT_LEN; ++i) begin
        @(posedge clk) begin
            if(i < BEAT_LEN) begin
                for (int j = 0; j < BEAT_SIZE; j++) begin
                    s_axis_tdata[j] <= abs2[i*BEAT_SIZE+j];
                end
                s_axis_tvalid <= 1;
                s_axis_tlast <= (i == BEAT_LEN-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
    #100
    for (int i  = 0; i <= BEAT_LEN; ++i) begin
        @(posedge clk) begin
            if(i < BEAT_LEN) begin
                for (int j = 0; j < BEAT_SIZE; j++) begin
                    s_axis_tdata[j] <= abs1[i*BEAT_SIZE+j];
                end
                s_axis_tvalid <= 1;
                s_axis_tlast <= (i == BEAT_LEN-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
end

// Check the result.
int j = 0;
always@ (posedge clk) begin
    if(svp_inst.stereo_match_inst.vld) begin
        for (int i = 0; i < ISSUE_WIDTH; i++)
            if(abs(svp_inst.stereo_match_inst.compare_val[i]) != abs(min[i+j*ISSUE_WIDTH])) begin
                $display("Mismatch: %d\n", i+j*ISSUE_WIDTH);
                $display("DUT: %d ", svp_inst.stereo_match_inst.compare_val[i]);
                $display("SIM: %d", min[i+j*ISSUE_WIDTH]);
                $stop;
            end
        j=j+1;
    end
end

function logic signed [DATA_WIDTH-1:0] abs(
    input logic signed [DATA_WIDTH-1:0] a
);
    if(a < 0)
        abs = -a;
    else
        abs = a;
endfunction

endmodule