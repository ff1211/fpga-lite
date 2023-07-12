`timescale 1ns/1ps
//****************************************************************
// Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
//
// File:
// tb.sv
// 
// Description:
// Testbenth of cal_abs_phase module.
// 
// Revision history:
// Version  Date        Author      Changes      
// 1.0      2022.11.14  ff          Initial version
//****************************************************************

module tb (
);

`define SIM

parameter RATIO_3TO2    = 8;
parameter RATIO_2TO1    = 8;
parameter TEST_LEN      = 1280;
parameter NOISE_CODE = 16'b10100000_00000000;

logic               clk;
logic               rst_n;
logic               vld_i;
logic signed [15:0] phase1_i;
logic signed [15:0] phase2_i;
logic signed [15:0] phase3_i;
logic               last_i;
logic               vld_o;
logic signed [15:0] abs_phase_o;
logic               last_o;
logic [15:0]        rel_phase_1 [TEST_LEN-1:0];
logic [15:0]        rel_phase_2 [TEST_LEN-1:0];
logic [15:0]        rel_phase_3 [TEST_LEN-1:0];
real                abs_phase_1 [TEST_LEN-1:0];

abs_phase_3steps #(
    .RATIO_3TO2     (   RATIO_3TO2  ),
    .RATIO_2TO1     (   RATIO_2TO1  ),
    .NOISE_CODE     (   NOISE_CODE  )
) dut (
    .clk            (   clk         ),
    .rst_n          (   rst_n       ),
    .vld_i          (   vld_i       ),
    .phase1_i       (   phase1_i    ),
    .phase2_i       (   phase2_i    ),
    .phase3_i       (   phase3_i    ),
    .last_i         (   last_i      ),
    .vld_o          (   vld_o       ),
    .abs_phase_o    (   abs_phase_o ),
    .last_o         (   last_o      )
);

// Create clock.
initial begin
    clk <= 0;
    rst_n <= 0;
    #200
    @(posedge clk) rst_n <= 1;
end
always #2 clk <= ~clk;

// Read ideal relative phase file.
initial begin
    $readmemb("/run/user/1000/gvfs/smb-share:server=nas305.local,share=home/project/code/matlab_sim/relative_phase/phase/rel_phase1.bin", rel_phase_1);
    $readmemb("/run/user/1000/gvfs/smb-share:server=nas305.local,share=home/project/code/matlab_sim/relative_phase/phase/rel_phase2.bin", rel_phase_2);
    $readmemb("/run/user/1000/gvfs/smb-share:server=nas305.local,share=home/project/code/matlab_sim/relative_phase/phase/rel_phase3.bin", rel_phase_3);
    // $readmemb("/run/user/1000/gvfs/smb-share:server=nas305.local,share=home/project/code/matlab_sim/relative_phase/phase/abs_phase1.bin", abs_phase_1);
end

// Input test data.
initial begin
    vld_i <= 0;
    last_i <= 0;
    wait(rst_n);
    #100
    for (int i = 0; i <= TEST_LEN; ++i) begin
        @(posedge clk) begin
            if(i < TEST_LEN) begin
                vld_i <= 1;
                phase1_i <= rel_phase_1[i];
                phase2_i <= rel_phase_2[i];
                phase3_i <= rel_phase_3[i];
                last_i <= (i == TEST_LEN - 1);
            end else begin
                vld_i <= 0;
                last_i <= 0;
            end
        end
    end
end

// Save result to a file.
int fd_w;

initial begin
    int j = 0;
    forever @(posedge clk) begin
        if(j == TEST_LEN)
            break;
        else if(vld_o) begin
            abs_phase_1[j] <= fix_2_real(abs_phase_o, 8);
            j++;
        end
    end

    fd_w = $fopen("/run/user/1000/gvfs/smb-share:server=nas305.local,share=home/project/code/matlab_sim/relative_phase/phase/result.txt", "w");
    for (int i = 0; i < TEST_LEN; ++i) begin
        $fdisplay(fd_w, "%.10f", abs_phase_1[i]);
    end
    $fclose(fd_w);
    $finish;
end

function real fix_2_real (input signed [15:0] x, input integer width);
    begin
        fix_2_real = real'(x) / real'(1 << width);
    end
endfunction

endmodule