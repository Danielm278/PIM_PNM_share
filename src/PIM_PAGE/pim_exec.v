`timescale 1ns/1ps

module pim_exec(
    input clk,
    input rst_n,
    input [4:0] ALU_Command,
    input [31:0] data1,
    input [31:0] data2,
    output [31:0] result,
    output result_valid
);

    reg [31:0] _debug_result_hold;
    always @(posedge clk) begin
        if (result_valid)
            _debug_result_hold <= result; // This forces result to be synthesized
    end
    
    // Supported operations
    localparam ADD_CMD = 5'b10000;
    localparam MUL_CMD = 5'b10010;

    wire EnableAdd   = (ALU_Command == ADD_CMD);
    wire EnableMult  = (ALU_Command == MUL_CMD);

    reg op_is_add, op_is_mul;
    reg [4:0] prev_ALU_Command;
    wire start = (prev_ALU_Command == 5'b00000 && ALU_Command != 5'b00000);
    wire start_Add = EnableAdd  & start;
    wire start_Mul = EnableMult & start;

    wire [31:0] resultAdd, resultMult;
    wire Add_Valid, Mul_Valid;

    // Remember the current operation type (add or mult) on start
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            prev_ALU_Command <= 5'b00000;
        else
            prev_ALU_Command <= ALU_Command;
    end

    // Latch which operation was launched
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_is_add <= 1'b0;
            op_is_mul <= 1'b0;
            end
        else if (start) begin
            op_is_add <= EnableAdd;
            op_is_mul <= EnableMult;
            end
    end

    // Result selection
    assign result       = op_is_add ? resultAdd : op_is_mul? resultMult: 0;
    assign result_valid = op_is_add ? Add_Valid : op_is_mul? Mul_Valid: 0;

    // Floating Point Multiplier IP (AXI-Streaming)
    floatMult FM1 (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_a_tvalid(start_Mul),
        //.s_axis_a_tready(start_Mul),
        .s_axis_a_tdata(data1),
        .s_axis_b_tvalid(start_Mul),
        //.s_axis_b_tready(start_Mul),
        .s_axis_b_tdata(data2),
        .m_axis_result_tdata(resultMult),
        .m_axis_result_tvalid(Mul_Valid)
        );

    // Floating Point Adder IP (AXI-Streaming)
    floatAdd FA1 (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axis_a_tvalid(start_Add),
        //.s_axis_a_tready(start_Add),
        .s_axis_a_tdata(data1),
        .s_axis_b_tvalid(start_Add),
        //.s_axis_b_tready(start_Add),
        .s_axis_b_tdata(data2),
        .m_axis_result_tdata(resultAdd),
        .m_axis_result_tvalid(Add_Valid)
    );

endmodule
