`timescale 1ns/1ps

module OP_Type_Decoder (
    input [5:0] Opcode,
    output reg OP_type
);

     // Opcodes unused by microblaze that we can use for our commands
    localparam PIM_1 = 6'b010100;
    localparam PIM_2 = 6'b010101;
    localparam PIM_3 = 6'b010111;
    localparam PIM_4 = 6'b110011;
    localparam PIM_5 = 6'b110111;
    
    // Opcodes used for loading data to proc
    localparam LBU  = 6'b110000; // Load Byte Unsigned
    localparam LBUI = 6'b111000; // Load Byte Unsigned Immediate
    localparam LHU  = 6'b110001; // Load HalfWord Unsigned
    localparam LHUI = 6'b111001; // Load HalfWord Unsigned Immediate
    localparam LW   = 6'b110010; // Load Word
    
    // Opcodes used for storing data from proc
    localparam SB  = 6'b110100; // Store Byte
    localparam SBI = 6'b111100; // Store Byte Immediate
    localparam SH  = 6'b110101; // Store Half word
    localparam SHI = 6'b111101; // Store Half word Immediate
    localparam SW  = 6'b110110; // Store Word
    

    always @(*) begin
        case (Opcode)
            // Memory opcodes (type = 0)
            LBU, LBUI, LHU, LHUI, LW,
            SB, SBI, SH, SHI, SW:
                OP_type = 1'b0;

            // PIM opcodes (type = 1)
            PIM_1, PIM_2, PIM_3, PIM_4, PIM_5:
                OP_type = 1'b1;

            // Default to memory type (can adjust if needed)
            default:
                OP_type = 1'b0;
        endcase
    end
endmodule