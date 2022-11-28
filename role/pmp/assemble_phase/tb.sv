`timescale 1ns/1ps

module tb (
);

`define SIM

parameter BEAT_SIZE = 8;
parameter DATA_WIDTH = 16;

logic clk;
logic rst_n;

initial begin
    clk <= 0;
    rst_n <= 0;
    #200
    @(posedge clk) rst_n <= 1;
end

always #2 clk <= ~clk;

logic [BEAT_SIZE*DATA_WIDTH-1:0]    s_axis_tdata;
logic                               s_axis_tvalid;
logic                               s_axis_tready;
logic                               s_axis_tlast;

phase_classify #(
    .DATA_WIDTH    (   16      ),
    .TAG_WIDTH     (   8       ),
    .TAG_CATAGORY  (   4       ),
    .BEAT_SIZE     (   8       ),
    .BUFFER_DEPTH  (   512     )
) dut (
    .aclk       (   clk     ),
    .aresetn    (   rst_n   ),

    .s_axis_tdata   (   s_axis_tdata    ),
    .s_axis_tvalid  (   s_axis_tvalid   ),
    .s_axis_tready  (   s_axis_tready   ),
    .s_axis_tlast   (   s_axis_tlast    ),
    
    .m_axis_tdata   (                   ),
    .m_axis_tvalid  (                   ),
    .m_axis_tready  (   1'b1            ),
    .m_axis_tlast   (                   )
);
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
                s_axis_tdata <= {8{16'd1}};
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
                s_axis_tdata <= {8{16'd2}};
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
                s_axis_tdata <= {8{16'd3}};
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
                s_axis_tdata <= {8{16'd4}};
                s_axis_tlast <= (i == PACKAGE_LEN-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
    #100
    for (int i  = 0; i <= PACKAGE_LEN/2; ++i) begin
        @(posedge clk) begin
            if(i < PACKAGE_LEN) begin
                s_axis_tvalid <= 1;
                s_axis_tdata <= {4{8'd0, 8'd1, 8'd2, 8'd3}};
                s_axis_tlast <= (i == PACKAGE_LEN/2-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
end

endmodule