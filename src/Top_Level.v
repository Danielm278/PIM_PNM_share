//TODO: Instantiate the PNMs, Check that it works

`timescale 1ns/1ps

module Top_Wrapper (
    input clk,
    input rst_n,

    // AXI interface to global scheduler
    input  [31:0] awaddr,
    input         awvalid,
    output        awready,
    input [7:0] awlen,
    input [2:0] awsize,
    input [1:0] awburst,

    input  [31:0] wdata,
    input         wvalid,
    input         wlast,
    output        wready,

    output [1:0]  bresp,
    output        bvalid,
    input         bready,

    input  [31:0] araddr,
    input         arvalid,
    output        arready,
    input [7:0] arlen,
    input [2:0] arsize,
    input [1:0] arburst,

    output [31:0] rdata,
    output [1:0]  rresp,
    output        rvalid,
    output        rlast,
    input         rready
    //probe
   // output PNM_done
);

    //Definable parameters
    localparam Page_Size = 11; //2^12 page memory size (1kb)
    localparam TOT_Address_Size = 16; //2^16 memory size (64kb)
    localparam DATA_WIDTH = 32; //32 bit data/address bus
    localparam NUM_PIM_EXECS = 2; //2 PIM executors
    localparam NUM_PIMS = 32;


    //Automatic parameters
    localparam Loc_Address_Size = TOT_Address_Size - Page_Size;
    localparam BLOCK_SIZE = 1<<Page_Size;
    
    wire PNM_done;
    (* DONT_TOUCH = "true", keep = "true" *) reg unused_awaddr, unused_araddr;
    
    
    always @(posedge clk) begin
        if(!rst_n) begin
            unused_awaddr <= 0;
            unused_araddr <= 0;
        end
        else begin
            unused_araddr <= |araddr[31:24];
            unused_awaddr <= |awaddr[31:24];
        end
    end

    // Internal interconnects from Global Scheduler to Local Schedulers
    wire [6*NUM_PIMS-1:0]     Command;
    wire [TOT_Address_Size*NUM_PIMS-1:0]    Address1;
    wire [TOT_Address_Size*NUM_PIMS-1:0]    Address2;
    wire [TOT_Address_Size*NUM_PIMS-1:0]    Address3;
    wire [DATA_WIDTH*NUM_PIMS-1:0]    DIN;
    wire [DATA_WIDTH*NUM_PIMS-1:0]    DOUT;
    wire [NUM_PIMS-1:0] DOUT_valid;
    wire [NUM_PIMS-1:0]       write_en ;

    //PNM to PIM/Global Scheduler interconnect wires
    wire [5:0]  Command_PNM;
    wire [TOT_Address_Size-1:0] Start_Addr, End_Addr, Res_Addr, Curr_Address;
    wire [TOT_Address_Size-1:0] Start_Addr_Latched, End_Addr_Latched, Res_Addr_Latched;
    wire [TOT_Address_Size-1:0] PNM_Res_Addr, PNM_Res_Addr_Relu, PNM_Res_Addr_Max, PNM_Res_Addr_Move;
    wire [DATA_WIDTH-1:0] From_PNM;
    wire PNM_Data_Ready;
    wire [NUM_PIMS-1:0] Accept_PNM;
    //wire PNM_done;

    //Local Scheduler to PIM Wires
    wire [5*NUM_PIMS-1:0]     Sched_Command;
    wire [Page_Size-1:0] PIM_ADDR1 [NUM_PIMS-1:0];
    wire [Page_Size-1:0] PIM_ADDR2 [NUM_PIMS-1:0];
    wire [Page_Size-1:0] PIM_ADDR3 [NUM_PIMS-1:0];
    wire [DATA_WIDTH-1:0] DIN_PIM [NUM_PIMS-1:0];

    //PNM internal Connections
    //wire done_Relu, done_Max_Pool;
    wire ReLu_En, Max_Pool_En, Move_En;
    wire ReLu_Start, Max_Pool_Start, Move_Start;


    // Internal interconnects between Local Schedulers and PIM Pages
    wire [DATA_WIDTH*NUM_PIMS-1:0]   To_PNM       ;
    wire [NUM_PIM_EXECS-1:0]    PIM_Busy     [NUM_PIMS-1:0];

    // DMA Interface Stubs (1 per PIM Page)
    wire [Page_Size-1:0]    dma_mirror_addr [NUM_PIMS-1:0];  // Optional, from DMA controller
    wire          dma_mirror_en   [NUM_PIMS-1:0];
    wire [DATA_WIDTH-1:0]   dma_mirror_data [NUM_PIMS-1:0];  // Output from PIM Page
    wire [DATA_WIDTH-1:0] DOUT_relu, DOUT_max, DOUT_move;
    wire [TOT_Address_Size-1:0] Curr_Address_Relu, Curr_Address_Max, Curr_Address_Move;
    wire PNM_Data_Ready_ReLu, PNM_Data_Ready_Max, PNM_Data_Ready_Move;
    wire buffer_full;

   // Wires to hold the locally derived addresses for each PIM page
    wire [Page_Size-1:0] pnm_in_addr_per_pim [NUM_PIMS-1:0];
    wire [Page_Size-1:0] pnm_res_addr_per_pim [NUM_PIMS-1:0];
    wire                 pnm_data_ready_per_pim [NUM_PIMS-1:0]; // Per-PIM data ready signal

    wire done_Max_Pool, done_Move, done_Relu;
 

    assign From_PNM = (ReLu_En)? DOUT_relu: (Max_Pool_En)? DOUT_max: (Move_En)? DOUT_move: 32'b0;
    assign Curr_Address = (ReLu_En)? Curr_Address_Relu: (Max_Pool_En)? Curr_Address_Max: (Move_En)? Curr_Address_Move: 32'b0;
    assign PNM_Data_Ready = (ReLu_En)? PNM_Data_Ready_ReLu: (Max_Pool_En)? PNM_Data_Ready_Max: (Move_En)? PNM_Data_Ready_Move: 1'b0;
    assign PNM_Res_Addr = ReLu_En? PNM_Res_Addr_Relu: (Max_Pool_En)? PNM_Res_Addr_Max: (Move_En)? PNM_Res_Addr_Move: 1'b0;



    PNM_Controller #(
        .Address_Size(TOT_Address_Size),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_PIMS(NUM_PIMS))
    i_PNM_Controller (
        .clk(clk),
        .rst_n(rst_n),
        .Sched_Command(Command_PNM),
        
//        //.DOUT(From_PNM),
        
//        .data_ready(PNM_Data_Ready),

        .done_Relu(done_Relu),
        .done_Max_Pool(done_Max_Pool),
        .done_Move(done_Move),
        .done(PNM_done),

        .ReLu_En(ReLu_En),
        .ReLu_Start(ReLu_Start),
        .Max_Pool_En(Max_Pool_En),
        .Max_Pool_Start(Max_Pool_Start),
        .Move_En(Move_En),
        .Move_Start(Move_Start),
        .Start_Addr(Start_Addr),
        .End_Addr(End_Addr),
        .Result_Addr(Res_Addr),

        .Result_Address_Latched(Res_Addr_Latched),
        .Start_Address_Latched(Start_Addr_Latched),
        .End_Address_Latched(End_Addr_Latched),
        .PIM_READY(Accept_PNM),
        .data_write(bvalid)
    );

    Max_Pooling_Controller  #(
        .Address_Size(TOT_Address_Size),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_PAGES(NUM_PIMS))
    i_Max_Pool (
        .clk(clk),
        .rst_n(rst_n),
        .done_Max_Pool(done_Max_Pool),
        .Max_Pooling_En(Max_Pool_En),
        .Max_Pooling_Start(Max_Pool_Start),
        .Start_Addr(Start_Addr_Latched),
        .End_Addr(End_Addr_Latched),
        .Result_Address(Res_Addr_Latched),
        .Curr_Address_Read(Curr_Address_Max), // Current address for memory access
        .Curr_Address_Write(PNM_Res_Addr_Max), // Current address for memory access
        .DIN_All(To_PNM),
        .DOUT(DOUT_max),
        .DOUT_Valid(PNM_Data_Ready_Max)
    );

    ReLu_Controller #(
        .Address_Size(TOT_Address_Size),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_PAGES(NUM_PIMS))
    i_ReLu_Controller(
        .clk(clk),
        .rst_n(rst_n),

        .done_Relu(done_Relu),
        .ReLu_En(ReLu_En),
        .Start_Addr(Start_Addr_Latched),
        .End_Addr(End_Addr_Latched),
        .Result_Address(Res_Addr_Latched),
        .Curr_Address_Read(Curr_Address_Relu),
        .Curr_Address_Write(PNM_Res_Addr_Relu),
        .DIN_All(To_PNM),
        .DOUT(DOUT_relu),
        .DOUT_Valid(PNM_Data_Ready_ReLu),
        .ReLu_Start(ReLu_Start)
        );
    
    Move_Controller #(
        .Address_Size(TOT_Address_Size),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_PAGES(NUM_PIMS))
    i_Move_Controller(
        .clk(clk),
        .rst_n(rst_n),

        .done_Move(done_Move),
        .Move_En(Move_En),
        .Start_Addr(Start_Addr_Latched),
        .End_Addr(End_Addr_Latched),
        .Result_Address(Res_Addr_Latched),
        .Curr_Address_Read(Curr_Address_Move),
        .Curr_Address_Write(PNM_Res_Addr_Move),
        .DIN_All(To_PNM),
        .DOUT(DOUT_move),
        .DOUT_Valid(PNM_Data_Ready_Move),
        .Move_Start(Move_Start)
        );

    // Instantiate Global Scheduler
    Global_scheduler #(
        .Page_Size(Page_Size),
        .Address_Size(TOT_Address_Size),
        .DATA_WIDTH(DATA_WIDTH),
        .Num_Local_Sched(NUM_PIMS)
    ) u_GlobalScheduler (
        .clk(clk),
        .rst_n(rst_n),

        .awaddr(awaddr),
        .awvalid(awvalid),
        .awready(awready),
        .awlen(awlen),
        .awburst(awburst),
        .awsize(awsize),

        .wdata(wdata),
        .wvalid(wvalid),
        .wready(wready),
        .wlast(wlast),        
        
        .bresp(bresp),
        .bvalid(bvalid),
        .bready(bready),

        .araddr(araddr),
        .arvalid(arvalid),
        .arready(arready),
        .arlen(arlen),
        .arsize(arsize),
        .arburst(arburst),

        .rdata(rdata),
        .rresp(rresp),
        .rvalid(rvalid),
        .rready(rready),
        .rlast(rlast),

       // .Local_Sched_Selector(Command),

        // Outputs to Local Schedulers and PIM Pages
        .Command_flat(Command)  ,
        .Address1_flat(Address1),
        .Address2_flat(Address2),
        .Address3_flat(Address3),
        .DIN_flat(DIN)          ,
        .write_en_flat(write_en),
        .DOUT_flat(DOUT),
        .DOUT_valid(DOUT_valid),

        //Outputs to PNM
        .Command_PNM(Command_PNM) ,
        .Address1_PNM(Start_Addr),
        .Address2_PNM(End_Addr),
        .Address3_PNM(Res_Addr),
        .PNM_Done(PNM_done)
    );

    // Generate multiple Local Schedulers and PIM Pages
    genvar i;
    generate
        for (i = 0; i < NUM_PIMS; i = i + 1) begin : PIM_BANKS

            assign pnm_in_addr_per_pim[i] = (i==Curr_Address[TOT_Address_Size-1:Page_Size]) ? Curr_Address[Page_Size-1:0] : {Page_Size{1'b0}};
            assign pnm_res_addr_per_pim[i] = (i==PNM_Res_Addr[TOT_Address_Size-1:Page_Size])  ? PNM_Res_Addr[Page_Size-1:0] : {Page_Size{1'b0}};
            
            // Activate data_ready for a specific PIM only if it's selected AND the global PNM_Data_Ready is high.
            assign pnm_data_ready_per_pim[i] = (i==PNM_Res_Addr[TOT_Address_Size-1:Page_Size])  & PNM_Data_Ready;

            // Local Scheduler Instance
            Local_Scheduler#(
                .DATA_WIDTH(DATA_WIDTH),
                .BLOCK_SIZE(BLOCK_SIZE),
                .NUM_EXEC(NUM_PIM_EXECS))
                u_LocalScheduler (
                .clk(clk),
                .rst_n(rst_n),
                .Command(Command[6*(i+1)-1:6*i]),
                .Sched_Command(Sched_Command[5*(i+1)-1:5*i]),
                .Address1(Address1[TOT_Address_Size*i + Page_Size-1:TOT_Address_Size*i]),
                .Address2(Address2[TOT_Address_Size*i + Page_Size-1:TOT_Address_Size*i]),
                .Address3(Address3[TOT_Address_Size*i + Page_Size-1:TOT_Address_Size*i]),
                .DIN(DIN[DATA_WIDTH*(i+1)-1:DATA_WIDTH*i]),
                .write_en(write_en[i]),
                //.DOUT(DOUT[DATA_WIDTH*(i+1)-1:DATA_WIDTH*i]),
                .PNM_Done(PNM_done),
                .buffer_full(buffer_full),
                .PIM_Busy(PIM_Busy[i]),
                .Address1_PIM(PIM_ADDR1[i]),
                .Address2_PIM(PIM_ADDR2[i]),
                .Address3_PIM(PIM_ADDR3[i]),
                .DIN_PIM(DIN_PIM[i])
            );

            // Stub DMA signals (could later be connected to a DMA controller)
            assign dma_mirror_addr[i] = 11'b0;
            assign dma_mirror_en[i]   = 1'b0;

            // PIM Page Instance
            pim_page #(
                .DATA_WIDTH(DATA_WIDTH),
                .BLOCK_SIZE(BLOCK_SIZE),
                .NUM_EXEC(NUM_PIM_EXECS)
            ) u_PIMPage (
                .clk(clk),
                .rst_n(rst_n),
                .Sched_Command(Sched_Command[5*(i+1)-1:5*i]),
                .PIM_Busy(PIM_Busy[i]),
                
                .Address_1(PIM_ADDR1[i]),
                .Address_2(PIM_ADDR2[i]),
                .Address_3(PIM_ADDR3[i]),
                .DIN(DIN_PIM[i]),
                .DOUT(DOUT[DATA_WIDTH*(i+1)-1:DATA_WIDTH*i]),
                .dma_addr(dma_mirror_addr[i]),
                .dma_en(dma_mirror_en[i]),
                .dma_we(dma_mirror_en[i]),
                .dma_din({DATA_WIDTH{1'b0}}),


                .From_PNM(From_PNM),
                .PNM_Data_Ready(pnm_data_ready_per_pim[i]),
                .To_PNM(To_PNM[DATA_WIDTH*(i+1)-1:DATA_WIDTH*i]),
                .PNM_In_Addr(pnm_in_addr_per_pim[i]),
                .PNM_Res_Addr(pnm_res_addr_per_pim[i]),
                .DOUT_valid(DOUT_valid[i]),
                .PNM_enable(Accept_PNM[i])
            );
        end
    endgenerate

endmodule