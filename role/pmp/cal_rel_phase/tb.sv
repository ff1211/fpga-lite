`timescale 1ns/1ps

module tb (
);

parameter PIPE_NUM = 8;
parameter BTH = 10;
parameter NOISE_CODE = 16'b10100000_00000000;
parameter BUFFER_DEPTH = 512;
parameter DATA_WIDTH = 16;
parameter TEST_LEN = 1000;

logic               clk;
logic               rst_n;
logic               vld_i;
logic [7:0]         pixel1_i;
logic [7:0]         pixel2_i;
logic [7:0]         pixel3_i;
logic [7:0]         pixel4_i;
logic               last_i;
logic               vld_o;
logic signed [15:0] phase_o;
logic               last_o;

initial begin
    clk <= 0;
    rst_n <= 0;
    #200
    @(posedge clk) rst_n <= 1;
end

always #5 clk <= ~clk;

logic [7:0] pixel_1 [TEST_LEN-1:0];
logic [7:0] pixel_2 [TEST_LEN-1:0];
logic [7:0] pixel_3 [TEST_LEN-1:0];
logic [7:0] pixel_4 [TEST_LEN-1:0];

real        modrate [TEST_LEN-1:0];
real        ideal_phase [TEST_LEN-1:0];

// DUT.
rel_phase_4steps # (
    .BTH        (   BTH         ),
    .NOISE_CODE (   NOISE_CODE  )
) dut (
    .clk        (   clk         ),
    .rst_n      (   rst_n       ),     
    .vld_i      (   vld_i       ),
    .pixel1_i   (   pixel1_i    ),
    .pixel2_i   (   pixel2_i    ),
    .pixel3_i   (   pixel3_i    ),
    .pixel4_i   (   pixel4_i    ),
    .last_i     (   last_i      ),
    .vld_o      (   vld_o       ),
    .phase_o    (   phase_o     ),
    .last_o     (   last_o      )
);

initial begin
    int diff42, diff13;
    for (int i = 0; i < TEST_LEN; i++) begin
        pixel_1[i] = $urandom_range(0, 255);
        pixel_2[i] = $urandom_range(0, 255);
        pixel_3[i] = $urandom_range(0, 255);
        pixel_4[i] = $urandom_range(0, 255);
        diff42 = int(pixel_4[i]) - int(pixel_2[i]);
        diff13 = int(pixel_1[i]) - int(pixel_3[i]);
        // Avoid the situation that diff13 == 0 or diff42 == 0.
        // When x in arctan2(y, x) equals to zero, the output of this function is depended on the implementation.
        // The result differs between cordic's and verilog's arctan2, which makes the comparison meaningless.
        while(diff13 == 0 || diff42 == 0) begin
            pixel_1[i] = $urandom_range(0, 255);
            pixel_2[i] = $urandom_range(0, 255);
            pixel_3[i] = $urandom_range(0, 255);
            pixel_4[i] = $urandom_range(0, 255);
            diff42 = int(pixel_4[i]) - int(pixel_2[i]);
            diff13 = int(pixel_1[i]) - int(pixel_3[i]);
        end
        modrate[i] = mod_rate(diff42, diff13);
        ideal_phase[i] = $atan2(diff42, diff13) / 3.141592654;
    end
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
                pixel1_i <= pixel_1[i];
                pixel2_i <= pixel_2[i];
                pixel3_i <= pixel_3[i];
                pixel4_i <= pixel_4[i];
                last_i <= (i == TEST_LEN - 1);
            end else begin
                vld_i <= 0;
                last_i <= 0;
            end
        end
    end
end

// Check results.
real max_error = 0.0;
int i = 0;
real phase_r, ideal_phase_t, modrate_t, dev;
initial begin
    forever begin
        @(posedge clk) begin
            if(vld_o) begin
                phase_r = fix_2_real(phase_o, 14);
                ideal_phase_t = ideal_phase[i];
                modrate_t = modrate[i];
                if (phase_o == NOISE_CODE)
                    dev = 0.0;
                else
                    dev = abs(phase_r - ideal_phase_t);
                if (dev > max_error)
                    max_error = dev;
                i = i + 1;

                if(last_o) begin
                    $display("The max error is:");
                    $display(max_error);
                    $display("\n");
                    $finish;
                end
            end
        end
    end
end

function real fix_2_real (input signed [15:0] x, input integer width);
    begin
        fix_2_real = real'(x) / real'(1 << width);
    end
endfunction

function [15:0] real_2_fix (input real x, input integer width);
    begin
        real scale = 2 ** width;
        real_2_fix = $rtoi(x * scale);
    end
endfunction

function real abs (input real x);
    begin
        abs = (x > 0)? x : -x;
    end
endfunction

function real mod_rate (input real x, input real y);
    begin
        mod_rate = 0.5 * $sqrt(x*x + y*y);
    end
endfunction


endmodule