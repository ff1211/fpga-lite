`timescale 1ns/1ps

module matrix_multi #(
    parameter DATA_WIDTH    = 16,
    parameter FORMAT        = 8
    parameter M_A           = 4,
    parameter N_A           = 4,
    parameter M_B           = 4,
    parameter N_B           = 4
) (
    input                               clk,
    input                               rst_n,
    input                               vld_i,
    input  signed [DATA_WIDTH-1:0]      A [M_A-1:0][N_A-1:0],
    input  signed [DATA_WIDTH-1:0]      B [M_B-1:0][N_B-1:0],
    output logic signed [DATA_WIDTH-1:0]C [M_A-1:0][N_B-1:0],
    output logic                        vld_o,
);

generate
if (N_A != M_B) begin
    $error("Error: Matrix A's cols should equal to matrix B's rows!");
    assert(0);
end else begin
    always @(posedge clk) begin
        for (int ii = 0; ii < N_B; ii++)
            for (int jj = 0; jj < N_A; jj++)
                C[ii][jj] <= A[ii][jj] * B[jj][ii];
    end
    always @(posedge clk) begin
        vld_o <= vld_i;
    end
end
endgenerate
endmodule