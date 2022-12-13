`timescale 1ns/1ps

module tb (
);

`define SIM

parameter BEAT_SIZE = 8;
parameter DATA_WIDTH = 16;
parameter PACKAGE_LEN_I = 128;
parameter PACKAGE_LEN_O = PACKAGE_LEN_I*2;

logic clk;
logic rst_n;

initial begin
    clk <= 0;
    rst_n <= 0;
    #200
    @(posedge clk) rst_n <= 1;
end

always #5 clk <= ~clk;

logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]               s_axis_tdata;
logic                                               s_axis_tvalid;
logic                                               s_axis_tready;
logic                                               s_axis_tlast;

logic [BEAT_SIZE-1:0][DATA_WIDTH-1:0]               m_axis_tdata;
logic                                               m_axis_tvalid;
logic                                               m_axis_tready;
logic                                               m_axis_tlast;

logic [PACKAGE_LEN_I-1:0][BEAT_SIZE*DATA_WIDTH-1:0] pixel_1;
logic [PACKAGE_LEN_I-1:0][BEAT_SIZE*DATA_WIDTH-1:0] pixel_2;
logic [PACKAGE_LEN_I-1:0][BEAT_SIZE*DATA_WIDTH-1:0] pixel_3;
logic [PACKAGE_LEN_I-1:0][BEAT_SIZE*DATA_WIDTH-1:0] pixel_4;

real                                                phase    [PACKAGE_LEN_O-1:0][BEAT_SIZE-1:0];
real                                                phase_o_f[BEAT_SIZE-1:0];
real                                                error_d  [BEAT_SIZE-1:0];
real                                                error    [PACKAGE_LEN_O-1:0][BEAT_SIZE-1:0];

cal_rel_phase #(
    .BEAT_SIZE      (   BEAT_SIZE   ),
    .DATA_WIDTH     (   DATA_WIDTH  ),
    .BUFFER_DEPTH   (   512         )
)cal_rel_phase_inst(
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

initial begin
    for (int i = 0; i < PACKAGE_LEN_I; i++) begin
        for(int j = 0; j < 16; j++) begin
            logic [7:0] pixel_1_t = $urandom_range(255, 1);
            logic [7:0] pixel_2_t = $urandom_range(255, 1);
            logic [7:0] pixel_3_t = $urandom_range(255, 1);
            logic [7:0] pixel_4_t = $urandom_range(255, 1);
            int diff42 = int'(pixel_4_t) - int'(pixel_2_t);
            int diff13 = int'(pixel_1_t) - int'(pixel_3_t);
            pixel_1[i][j*8+:8] = pixel_1_t;
            pixel_2[i][j*8+:8] = pixel_2_t;
            pixel_3[i][j*8+:8] = pixel_3_t;
            pixel_4[i][j*8+:8] = pixel_4_t;
            if(j < 8)
                phase[i*2][j] = $atan2(diff42, diff13) / 3.141592654;
            else
                phase[i*2+1][j-8] = $atan2(diff42, diff13) / 3.141592654;
        end
    end
end

int i = 0;
initial begin
    s_axis_tvalid <= 0;
    s_axis_tlast <= 0;
    wait(rst_n);
    #400
    for (int i  = 0; i <= PACKAGE_LEN_I; ++i) begin
        @(posedge clk) begin
            if(i < PACKAGE_LEN_I) begin
                s_axis_tvalid <= 1;
                s_axis_tdata <= pixel_1[i];
                s_axis_tlast <= (i == PACKAGE_LEN_I-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
    #100
    for (int i  = 0; i <= PACKAGE_LEN_I; ++i) begin
        @(posedge clk) begin
            if(i < PACKAGE_LEN_I) begin
                s_axis_tvalid <= 1;
                s_axis_tdata <= pixel_2[i];
                s_axis_tlast <= (i == PACKAGE_LEN_I-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
    #100
    for (int i  = 0; i <= PACKAGE_LEN_I; ++i) begin
        @(posedge clk) begin
            if(i < PACKAGE_LEN_I) begin
                s_axis_tvalid <= 1;
                s_axis_tdata <= pixel_3[i];
                s_axis_tlast <= (i == PACKAGE_LEN_I-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
    #100
    for (int i  = 0; i <= PACKAGE_LEN_I; ++i) begin
        @(posedge clk) begin
            if(i < PACKAGE_LEN_I) begin
                s_axis_tvalid <= 1;
                s_axis_tdata <= pixel_4[i];
                s_axis_tlast <= (i == PACKAGE_LEN_I-1)? 1'b1 : 1'b0;
            end else begin
                s_axis_tvalid <= 1'b0;
                s_axis_tlast <= 1'b0;
            end
        end
    end
end

// Check results.
int i = 0;
real max_error = 0.0;
assign m_axis_tready = 1;
always @(posedge clk) begin
    if(m_axis_tready & m_axis_tvalid) begin
        for (int j = 0; j < BEAT_SIZE; j++) begin
            phase_o_f[j] = fix_2_float(m_axis_tdata[j]);
            error_d[j] = phase_o_f[j] - phase[i][j];
            error[i][j] = error_d[j];
            if(abs(error_d[j]) > max_error)
                max_error = abs(error_d[j]);
        end
        i = i + 1;
    end
end

function real fix_2_float;
    input signed [DATA_WIDTH-1:0] x;
    begin
        fix_2_float = real'(x) / real'(1 << 13);
    end
endfunction

function real abs;
    input real x;
    begin
        abs = (x > 0)? x : -x;
    end
endfunction


endmodule