`timescale 1ns/1ps

module Seperator (
    (* DONT_TOUCH = "TRUE" *) input [55:0] Combined_Command,
    input Enable,
    output reg [5:0] Opcode,
    output reg [15:0] Address_1,
    output reg [15:0] Address_2,
    output reg [15:0] Address_3,
    output reg [31:0] DIN
);

always @(*) begin
    if (Enable) begin
        Opcode     = Combined_Command[55:50];

        Address_1  = Combined_Command[49:34];  // Highest 16 bits of address section

        //The DIN bits will overlap with the 2nd and 3rd address bits
        //this is because if we utalize the DIN we are in a mem command 
        //which will not use the Address2,3 and if we use those addresses
        //we are in an ALU type command and won't use DIN 
        Address_2  = Combined_Command[31:16];  // Middle 16 bits
        Address_3  = Combined_Command[15:0];   // Lowest 16 bits of address section

        DIN        = Combined_Command[31:0];   // Always the lower 32 bits
    end else begin
        Opcode     = 6'd0;
        Address_1  = 16'd0;
        Address_2  = 16'd0;
        Address_3  = 16'd0;
        DIN        = 32'd0;
    end
end

endmodule