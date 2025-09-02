`timescale 1ns/1ps

module Sched_decode(
    input [5:0] Command,
    output reg [4:0] Sched_command
    );
	//localparam PIM_1 = 6'b010100;->addFloat
    //localparam PIM_2 = 6'b010101;->mulFloat
    //localparam PIM_3 = 6'b010111;->relu_PNM
    //localparam PIM_4 = 6'b110011;->max_pooling_PNM
    //localparam PIM_5 = 6'b110111; -> MOVE
    // Opcodes used for loading data to proc
    localparam LBU  = 6'b110000; // Load Byte Unsigned
    localparam LHU  = 6'b110001; // Load HalfWord Unsigned
    localparam LHUI = 6'b111001; // Load HalfWord Unsigned Immediate
    localparam LW   = 6'b110010; // Load Word
    
    // Opcodes used for storing data from proc
    localparam SB  = 6'b110100; // Store Byte
    localparam SH  = 6'b110101; // Store Half word
    localparam SW  = 6'b110110; // Store Word
    
	always @(*) begin
		case(Command)
			6'b010100:
				Sched_command <= 5'b10000;
			6'b010101:
				Sched_command <= 5'b10010;
			6'b010111:
				Sched_command <= 5'b11000;
			6'b110011:
				Sched_command <= 5'b11001;
			6'b110111:
				Sched_command <= 5'b11011;
			LBU:
				Sched_command <= 5'b01011;
			LHU:
				Sched_command <= 5'b01010;

			LW:
				Sched_command <= 5'b01001;
			SB:
				Sched_command <= 5'b00011;
			SH:
				Sched_command <= 5'b00010;

			SW:
				Sched_command <= 5'b00001;


			default:
				Sched_command <= 0;
		endcase
	end
	
	
endmodule
