`timescale 1ns/1ps

module Local_Scheduler #(parameter DATA_WIDTH = 32, BLOCK_SIZE = 1024, NUM_EXEC = 2) (
    input clk,
    input rst_n,

    input [5:0] Command,
    output reg [4:0] Sched_Command,

    input [$clog2(BLOCK_SIZE)-1:0] Address1,
    input [$clog2(BLOCK_SIZE)-1:0] Address2,
    input [$clog2(BLOCK_SIZE)-1:0] Address3,
    output [$clog2(BLOCK_SIZE)-1:0] Address1_PIM,
    output [$clog2(BLOCK_SIZE)-1:0] Address2_PIM,
    output [$clog2(BLOCK_SIZE)-1:0] Address3_PIM,
    output [DATA_WIDTH-1:0] DIN_PIM,
    input [DATA_WIDTH-1:0] DIN,
    //output [DATA_WIDTH-1:0] DOUT,

    input write_en,
    output buffer_full,
    input PNM_Done,
    input [NUM_EXEC-1:0] PIM_Busy
);

    // Command Definitions
    localparam PIM_1 = 6'b010100;
    localparam PIM_2 = 6'b010101;
    localparam PIM_3 = 6'b010111;
    localparam PIM_4 = 6'b110011;
    localparam PIM_5 = 6'b110111;

    localparam LBU  = 6'b110000;
    localparam LBUI = 6'b111000;
    localparam LHU  = 6'b110001;
    localparam LHUI = 6'b111001;
    localparam LW   = 6'b110010;

    localparam SB  = 6'b110100;
    localparam SBI = 6'b111100;
    localparam SH  = 6'b110101;
    localparam SHI = 6'b111101;
    localparam SW  = 6'b110110;

    localparam IDLE    = 2'b00;
    localparam FETCH   = 2'b01;
    localparam EXECUTE = 2'b11;
    localparam RESULT  = 2'b10;

    wire [5:0] Fetch_Command;
    wire [4:0] Decoded_command;
    wire empty;
    wire  read_en;
    
    reg [6 + 3 * $clog2(BLOCK_SIZE) + DATA_WIDTH-1:0] Combined_command;

    // Fetched data wires from FIFO
    wire [$clog2(BLOCK_SIZE)-1:0] Address_1, Address_2, Address_3;
    wire [DATA_WIDTH-1:0] Data_in;

    // Latched (registered) versions
    //reg [4:0] latched_decoded_command;
    reg [$clog2(BLOCK_SIZE)-1:0] latched_A1, latched_A2, latched_A3;
    reg [DATA_WIDTH-1:0] latched_DIN;

    assign DOUT = 32'd0;  // Could be used later if needed

    wire type_PIM = Sched_Command[4] & ~Sched_Command[3];
    wire [6 + 3 * $clog2(BLOCK_SIZE) + DATA_WIDTH-1:0] store_command = (Command == LBU)? {Command, Address1, Address2, Address3, DIN}: Combined_command;

    reg [1:0] state, next_state;
    reg PNM_Lock;

    assign Address1_PIM = latched_A1;
    assign Address2_PIM = latched_A2;
    assign Address3_PIM = latched_A3;
    assign DIN_PIM = latched_DIN;
    
    assign read_en = !empty && state == FETCH;
    //assign DIN_PIM = DIN;
    
    always @(posedge clk) begin
        if(!rst_n) Combined_command <= 0;
        else Combined_command <= {Command, Address1, Address2, Address3, DIN};
    end

    always @(posedge clk) begin
        if(!rst_n) PNM_Lock <= 0;
        else if (PNM_Done && PNM_Lock) PNM_Lock <= 0;
        else if(Decoded_command[4:3] == 2'b11 && !PNM_Done) PNM_Lock <= 1;
    end

    // FSM State Register
    always @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // FSM Next-State Logic
    always @(*) begin
        case (state)
            IDLE:
                next_state = FETCH;

            FETCH:
                if (!empty)
                    next_state = EXECUTE;
                else
                    next_state = FETCH;

            EXECUTE:
                if (type_PIM && !check_PIM(PIM_Busy))
                    next_state = EXECUTE;
                else if (PNM_Lock) next_state = EXECUTE;
                //else if (Decoded_command[4:3] == 2'b11) next_state = EXECUTE;
                else if (!type_PIM || (type_PIM && check_PIM(PIM_Busy)))
                    next_state = RESULT;
                else
                    next_state = EXECUTE;

            RESULT:
                if (PNM_Lock) next_state = EXECUTE;
                else next_state = IDLE;

            default:
                next_state = IDLE;
        endcase
    end

    // FSM Output Logic
    always @(posedge clk) begin
        if (!rst_n) begin
            Sched_Command <= 5'd0;
            //latched_decoded_command <= 5'd0;
//            latched_A1 <= 0;
//            latched_A2 <= 0;
//            latched_A3 <= 0;
//            latched_DIN <= 0;
        end else begin
            case (state)
                IDLE: begin
                    Sched_Command <= 5'd0;
                end

                FETCH: begin
                    Sched_Command <= 5'd0;
                end

                EXECUTE: begin
                    Sched_Command <= Decoded_command;
                end

                RESULT: begin
                    if(PNM_Done)
                    Sched_Command <= 0;
                end

                default: begin
                    Sched_Command <= 5'bx;
                end
            endcase
        end
    end

    // Latch FIFO outputs when reading
    always @(posedge clk) begin
        if (!rst_n) begin
            //latched_decoded_command <= 0;
            latched_A1 <= 0;
            latched_A2 <= 0;
            latched_A3 <= 0;
            latched_DIN <= 0;
        end else begin
            //latched_decoded_command <= Decoded_command;
            latched_A1 <= Address_1;
            latched_A2 <= Address_2;
            latched_A3 <= Address_3;
            latched_DIN <= Data_in;
        end
    end

    // Check for any available PIM unit
    function check_PIM(input [NUM_EXEC-1:0] busy_pim);
        integer i;
        begin
            check_PIM = 0;
            for (i = 0; i < NUM_EXEC; i = i + 1) begin
                if (!busy_pim[i])
                    check_PIM = 1;
            end
        end
    endfunction

    // FIFO Queue: command + 3 addresses + data
    (* keep_hierarchy = "yes" *)
    Sched_queue #(
        .FIFO_DEPTH(32),
        .FIFO_WIDTH(6 + 3 * $clog2(BLOCK_SIZE) + DATA_WIDTH)
    ) i_queue (
        .clk(clk),
        .rst_n(rst_n),
        .write_en(write_en),
        .data_in(store_command),
        .empty(empty),
        .read_en(read_en),
        .full(buffer_full),
        .data_out({Fetch_Command, Address_1, Address_2, Address_3, Data_in})
    );

    // Decode command to scheduler format
    Sched_decode i_decode (
        .Command(Fetch_Command),
        .Sched_command(Decoded_command)
    );

endmodule
