    module PNM_Controller  #(parameter DATA_WIDTH = 32, Address_Size = 16, NUM_PIMS = 32) (
        input clk,
        input rst_n,
        input [5:0] Sched_Command,
        
        input [Address_Size-1:0] Start_Addr,
        input [Address_Size-1:0] End_Addr,
        input [Address_Size-1:0] Result_Addr,
    
        output reg [Address_Size-1:0] Result_Address_Latched,
        output reg [Address_Size-1:0] Start_Address_Latched,
        output reg [Address_Size-1:0] End_Address_Latched,
        //output [DATA_WIDTH-1:0] DOUT,
        
    
        input done_Relu,
        input done_Max_Pool,
        input done_Move,
        output done,
    
        output ReLu_En,
        output Max_Pool_En,
        output Move_En,
        
        output ReLu_Start,
        output Max_Pool_Start,
        output Move_Start,
        input [NUM_PIMS-1:0] PIM_READY,
        input data_write
    );
        localparam RELU = 6'b010111; //->relu_PNM
        localparam MAX_POOL = 6'b110011; //->max_pooling_PNM
        localparam MOVE = 6'b110111; //->move_pooling_PNM
        localparam POOL_SIZE = 2*2;
        
//        reg command_taken;
        reg [NUM_PIMS-1:0] relevant_pages_mask;
        wire PIM_ready_eval;
        wire [Address_Size-1:0] End_Result_Addr;
        integer i;
        reg [5:0] Sched_Command_Latch;    
//        wire write_en;
//        wire empty, buffer_full;
//        reg read_en;
    
    
    
//        assign write_en = data_write && ((Sched_Command == RELU) || (Sched_Command == MAX_POOL)|| (Sched_Command ==MOVE));
        assign PIM_ready_eval = &relevant_pages_mask;
        
        assign ReLu_Start = (Sched_Command == RELU && data_write)? 1'b1:1'b0;
        assign Max_Pool_Start = (Sched_Command == MAX_POOL && data_write)? 1'b1:1'b0;
        assign Move_Start = (Sched_Command == MOVE && data_write)? 1'b1:1'b0;
        
        assign ReLu_En = (Sched_Command_Latch == RELU & PIM_ready_eval)? 1'b1:1'b0;
        assign Max_Pool_En = (Sched_Command_Latch == MAX_POOL & PIM_ready_eval)? 1'b1:1'b0;
        assign Move_En = (Sched_Command_Latch == MOVE & PIM_ready_eval)? 1'b1:1'b0;
        
        assign End_Result_Addr = (End_Address_Latched - Start_Address_Latched +1) +Result_Address_Latched;
        
        assign done = done_Relu & done_Max_Pool & done_Move;
        
        always @(*) begin
            for(i = 0; i < NUM_PIMS; i = i+1) begin
                if( i >= Start_Address_Latched[Address_Size-1: Address_Size-$clog2(NUM_PIMS)] && i <= End_Address_Latched[Address_Size-1: Address_Size-$clog2(NUM_PIMS)]) begin
                    relevant_pages_mask[i] = PIM_READY[i];
                end
                else if( i >= Result_Address_Latched[Address_Size-1: Address_Size-$clog2(NUM_PIMS)] && i <= End_Result_Addr[Address_Size-1: Address_Size-$clog2(NUM_PIMS)]) begin
                    relevant_pages_mask[i] = PIM_READY[i];
                end
                else relevant_pages_mask[i] = 1'b1;
            end
        end
        
        always @(posedge clk) begin
            if(!rst_n) begin
                Sched_Command_Latch <= 0;
                Start_Address_Latched <= 0;
                End_Address_Latched <= 0;
                Result_Address_Latched <= 0;
//                command_taken <= 0;
            end
            if (ReLu_Start | Max_Pool_Start | Move_Start) begin
                if(Start_Address_Latched == 0 && End_Address_Latched == 0 && Result_Address_Latched == 0) begin
                    Sched_Command_Latch <= Sched_Command;
                    Start_Address_Latched <= Start_Addr;
                    End_Address_Latched <= End_Addr;
                    Result_Address_Latched <= Result_Addr;
//                    command_taken <= 1;
                end
            end
            else if (done) begin
                Start_Address_Latched <= 0;
                End_Address_Latched <= 0;
                Result_Address_Latched <= 0;
                Sched_Command_Latch <= 0;
                
                //if(Sched_Command[4:3] != RELU && Sched_Command[4:3] != MAX_POOL && Sched_Command[4:3] != MAX_POOL) begin
//                command_taken <= 0;
                //end
            end 
            
        end

//        // FIFO Queue: command + 3 addresses
//    Sched_queue #(
//        .FIFO_DEPTH(8),
//        .FIFO_WIDTH(6 + 3 * Address_Size)
//    ) i_queue (
//        .clk(clk),
//        .rst_n(rst_n),
//        .write_en(write_en),
//        .data_in({Sched_Command, Start_Addr, End_Addr, Result_Addr}),
//        .empty(empty),
//        .read_en(read_en),
//        .full(buffer_full),
//        .data_out({Sched_Command_Latch, Start_Address_Latched, End_Address_Latched, Result_Address_Latched})
//    );

        
    endmodule
