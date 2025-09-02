`timescale 1ns/1ps

module ReLu (
    input  [31:0] in_val,  // 4 × 32-bit = 128-bit bus
    output [31:0] out_val
);
    assign out_val[31:0] = (in_val[31] == 1'b1) ? 32'd0 : in_val[31:0];
endmodule