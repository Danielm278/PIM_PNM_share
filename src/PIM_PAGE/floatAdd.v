`timescale 1ns/1ps

module floatAdd (
    input Enable,
    input [31:0] floatA, floatB,
    output reg [31:0] sum
);

reg sign;
reg [7:0] exponent;
reg [22:0] mantissa;
reg [7:0] exponentA, exponentB;
reg [23:0] fractionA, fractionB, fraction;
reg [7:0] shiftAmount;
reg cout;

always @(*) begin
    if (Enable) begin
        exponentA = floatA[30:23];
        exponentB = floatB[30:23];
        fractionA = {1'b1,floatA[22:0]};
        fractionB = {1'b1,floatB[22:0]}; 
        exponent = exponentA;

        if (floatA == 0) begin
            sum = floatB;
        end else if (floatB == 0) begin
            sum = floatA;
        end else if (floatA[30:0] == floatB[30:0] && floatA[31]^floatB[31]==1'b1) begin
            sum = 0;
        end else begin
            if (exponentB > exponentA) begin
                shiftAmount = exponentB - exponentA;
                fractionA = fractionA >> shiftAmount;
                exponent = exponentB;
            end else if (exponentA > exponentB) begin 
                shiftAmount = exponentA - exponentB;
                fractionB = fractionB >> shiftAmount;
                exponent = exponentA;
            end

            if (floatA[31] == floatB[31]) begin
                {cout, fraction} = fractionA + fractionB;
                if (cout == 1'b1) begin
                    {cout, fraction} = {cout, fraction} >> 1;
                    exponent = exponent + 1;
                end
                sign = floatA[31];
            end else begin
                if (floatA[31] == 1'b1) begin
                    {cout, fraction} = fractionB - fractionA;
                end else begin
                    {cout, fraction} = fractionA - fractionB;
                end
                sign = cout;
                if (cout == 1'b1) begin
                    fraction = -fraction;
                end

                // Normalize the result
                if (fraction[23] == 0) begin
                    repeat (23) begin
                        if (fraction[23] == 0) begin
                            fraction = fraction << 1;
                            exponent = exponent - 1;
                        end
                    end
                end
            end
            mantissa = fraction[22:0];
            sum = {sign, exponent, mantissa};
        end
    end else begin
        sum = 32'b0;  // Tri-state output or leave unchanged depending on your need
    end
end

endmodule

