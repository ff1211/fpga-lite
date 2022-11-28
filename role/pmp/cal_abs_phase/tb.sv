`timescale 1ns/1ps

module tb (
);

`define SIM

parameter PHASE_NUM = 8;
parameter DATA_WIDTH = 16;

logic clk;
logic rst_n;

initial begin
    clk <= 0;
    rst_n <= 0;
    #200
    @(posedge clk) rst_n <= 1;
end

always #5 clk <= ~clk;

logic [PHASE_NUM*DATA_WIDTH-1:0]s_axis_tdata;
logic                           s_axis_tvalid;
logic                           s_axis_tready;
logic                           s_axis_tlast;

logic [PHASE_NUM*DATA_WIDTH-1:0]m_axis_tdata;
logic                           m_axis_tvalid;
logic                           m_axis_tready;
logic                           m_axis_tlast;

cal_abs_phase #(
    .PHASE_NUM      (   PHASE_NUM   ),
    .DATA_WIDTH     (   DATA_WIDTH  ),
    .RATIO_3TO2     (   8       ),
    .RATIO_2TO1     (   8       ),
    .BUFFER_DEPTH   (   512     )
)cal_abs_phase_inst(
    .aclk       (   clk     ),
    .aresetn    (   rst_n   ),

    .s_axis_tdata   (   s_axis_tdata    ),
    .s_axis_tvalid  (   s_axis_tvalid   ),
    .s_axis_tready  (   s_axis_tready   ),
    .s_axis_tlast   (   s_axis_tlast    ),
    
    .m_axis_tdata   (   m_axis_tdata    ),
    .m_axis_tvalid  (   m_axis_tvalid   ),
    .m_axis_tready  (   m_axis_tready   ),
    .m_axis_tlast   (   m_axis_tlast    )
);
assign m_axis_tready = 1'b1;

parameter PACKAGE_LEN = 256;
int i = 0;
initial begin
    s_axis_tvalid <= 0;
    s_axis_tlast <= 0;
    wait(rst_n);
    for (int i  = 0; i <= PACKAGE_LEN; ++i) begin
        @(posedge clk) begin
            if(i < PACKAGE_LEN) begin
                s_axis_tvalid <= 1;
                s_axis_tdata <= {8{16'b01010011_10100001}};
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
                s_axis_tvalid <= 1;
                s_axis_tdata <= {8{16'b00100010_01001001}};
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
                s_axis_tvalid <= 1;
                s_axis_tdata <= {8{16'b01000011_00101010}};
                s_axis_tlast <= (i == PACKAGE_LEN-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
end

endmodule