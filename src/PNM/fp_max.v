`timescale 1ns/1ps

module fp_gt (
    input  wire [31:0] a,  // IEEE-754 single-precision float
    input  wire [31:0] b,
    output wire        gt  // a > b
);

    wire sign_a = a[31];
    wire sign_b = b[31];

    wire [7:0]  exp_a = a[30:23];
    wire [7:0]  exp_b = b[30:23];
    wire [22:0] frac_a = a[22:0];
    wire [22:0] frac_b = b[22:0];

    wire [31:0] abs_a = {1'b0, a[30:0]};
    wire [31:0] abs_b = {1'b0, b[30:0]};

    wire a_gt_b_unsigned = (a[30:0] > b[30:0]);
    wire a_lt_b_unsigned = (a[30:0] < b[30:0]);

    assign gt = (sign_a != sign_b) ? (!sign_a) :  // Different signs: positive is greater
                (sign_a == 1'b0)  ? a_gt_b_unsigned : // Both positive: standard comparison
                                   a_lt_b_unsigned;  // Both negative: reversed comparison

endmodule