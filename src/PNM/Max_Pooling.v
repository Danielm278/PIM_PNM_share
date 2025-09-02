`timescale 1ns/1ps

module fp_max_pool_2x2 (
    input  wire [31:0] in0, in1, in2, in3,  // IEEE-754 single-precision floats
    output wire [31:0] out
);
    wire [31:0] max0, max1;

    wire gt01, gt23, gt;

    fp_gt cmp01 (.a(in0), .b(in1), .gt(gt01));
    assign max0 = gt01 ? in0 : in1;

    fp_gt cmp23 (.a(in2), .b(in3), .gt(gt23));
    assign max1 = gt23 ? in2 : in3;

    fp_gt cmp   (.a(max0), .b(max1), .gt(gt));
    assign out = gt ? max0 : max1;
endmodule