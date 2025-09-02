`timescale 1ns/1ps

module floatMult (
    input Enable,
    input [31:0] floatA, floatB,
    output reg [31:0] product
);

reg sign;
reg [7:0] exponent;
reg [22:0] mantissa;
reg [23:0] fractionA, fractionB;
reg [47:0] fraction;
reg found;

reg guard, round, sticky;
reg [22:0] rounded_mantissa;
reg carry;

integer i;

always @(*) begin
    if (Enable) begin
        if (floatA == 0 || floatB == 0) begin
            product = 0;
        end else begin
            sign = floatA[31] ^ floatB[31];
            exponent = floatA[30:23] + floatB[30:23] - 8'd127;

            fractionA = {1'b1, floatA[22:0]};
            fractionB = {1'b1, floatB[22:0]};
            fraction = fractionA * fractionB;

            // Normalize the result (align MSB at bit 47)
            found = 0;
            for (i = 47; i > 24; i = i - 1) begin
                if (!found && fraction[i] == 1'b1) begin
                    fraction = fraction << (47 - i);
                    exponent = exponent - (47 - i);
                    found = 1;
                end
            end

            // Extract bits for rounding
            mantissa = fraction[46:24];
            guard    = fraction[23];
            round    = fraction[22];
            sticky   = |fraction[21:0];

            // Round-to-nearest, ties-to-even
            carry = 0;
            if (guard && (round || sticky)) begin
                {carry, rounded_mantissa} = mantissa + 1;
            end else begin
                rounded_mantissa = mantissa;
            end

            // Handle mantissa overflow due to rounding
            if (carry) begin
                exponent = exponent + 1;
                mantissa = 23'b10000000000000000000000;
            end else begin
                mantissa = rounded_mantissa;
            end
            
            exponent = exponent + fraction[47];

            product = {sign, exponent, mantissa};
        end
    end else begin
        product = 32'b0;
    end
end

endmodule
