`timescale 1ns/1ps

module Global_scheduler #(
    parameter Page_Size = 10,
    parameter Address_Size = 16,
    parameter DATA_WIDTH = 32,
    parameter Num_Local_Sched = 64
)(
    input clk,
    input rst_n,

    // AXI Write Address Channel
    (* DONT_TOUCH = "TRUE" *) input [31:0] awaddr,
    (* DONT_TOUCH = "TRUE" *) input awvalid,
    (* DONT_TOUCH = "TRUE" *) input [7:0] awlen,
    (* DONT_TOUCH = "TRUE" *) input [2:0] awsize,
    (* DONT_TOUCH = "TRUE" *) input [1:0] awburst,
    (* DONT_TOUCH = "TRUE" *) output reg awready,
    
    
    // AXI Write Data Channel
    (* DONT_TOUCH = "TRUE" *) input [DATA_WIDTH-1:0] wdata,
    (* DONT_TOUCH = "TRUE" *) input wvalid,
    (* DONT_TOUCH = "TRUE" *) input wlast,
    (* DONT_TOUCH = "TRUE" *) output reg wready,

    // AXI Write Response Channel
    (* DONT_TOUCH = "TRUE" *) output reg [1:0] bresp,
    (* DONT_TOUCH = "TRUE" *) output reg bvalid,
    (* DONT_TOUCH = "TRUE" *) input bready,

    // AXI Read Address Channel
    (* DONT_TOUCH = "TRUE" *) input [31:0] araddr,
    (* DONT_TOUCH = "TRUE" *) input arvalid,
    (* DONT_TOUCH = "TRUE" *) input [7:0] arlen,
    (* DONT_TOUCH = "TRUE" *) input [2:0] arsize,
    (* DONT_TOUCH = "TRUE" *) input [1:0] arburst,
    (* DONT_TOUCH = "TRUE" *) output reg arready,

    // AXI Read Data Channel
    (* DONT_TOUCH = "TRUE" *) output reg [DATA_WIDTH-1:0] rdata,
    (* DONT_TOUCH = "TRUE" *) output reg [1:0] rresp,
    (* DONT_TOUCH = "TRUE" *) output reg rvalid,
    (* DONT_TOUCH = "TRUE" *) output reg rlast,
    (* DONT_TOUCH = "TRUE" *) input wire rready,


    //input from pim page to PNM
    //input [31:0] To_PNM,

    // Outputs to Local Schedulers and PIM Pages
    output [Num_Local_Sched*6-1:0]        Command_flat ,
    output [Num_Local_Sched*Address_Size-1:0]       Address1_flat,
    output [Num_Local_Sched*Address_Size-1:0]       Address2_flat,
    output [Num_Local_Sched*Address_Size-1:0]       Address3_flat,
    output [Num_Local_Sched*DATA_WIDTH-1:0]       DIN_flat     ,
    input  [Num_Local_Sched*DATA_WIDTH-1:0]       DOUT_flat    ,
    input [Num_Local_Sched-1:0] DOUT_valid,
    output [Num_Local_Sched-1:0]            write_en_flat,
    
    output reg [5:0]        Command_PNM ,
    output reg [Address_Size-1:0]        Address1_PNM,
    output reg [Address_Size-1:0]        Address2_PNM,
    output reg [Address_Size-1:0]        Address3_PNM,
    input PNM_Done
);

    reg [5:0]  Command           [Num_Local_Sched-1: 0];
    reg [Page_Size-1:0]  Address1          [Num_Local_Sched-1: 0];
    reg [Page_Size-1:0]  Address2          [Num_Local_Sched-1: 0];
    reg [Page_Size-1:0]  Address3          [Num_Local_Sched-1: 0];
    reg [DATA_WIDTH-1:0] DIN               [Num_Local_Sched-1: 0];
    reg [Num_Local_Sched-1: 0]   write_en              ;
    reg [Num_Local_Sched-1: 0]   write_ps              ;
    
    reg [7:0] read_count;
    reg [DATA_WIDTH-1:0] raddr_reg;
    reg rvalid_next;
    reg rlast_ps;
    
    reg [7:0] write_count;
    reg [DATA_WIDTH-1:0] waddr_reg;
    
    reg [1:0] wburst_type;
    wire [31:0] wbeat_size;
    wire [31:0] wwrap_size = (awlen+1)*wbeat_size;
    wire [31:0] wwrap_mask = wwrap_size-1;
    reg [31:0] wwrap_mask_reg;


    reg [1:0] rburst_type;
    wire [31:0] rbeat_size;
    wire [31:0] rwrap_size = (arlen+1)*rbeat_size;
    wire [31:0] rwrap_mask = rwrap_size-1;
    reg [31:0] rwrap_mask_reg;
    
    wire [DATA_WIDTH-1:0] DOUT;
    wire fifo_write_en;
    wire [DATA_WIDTH-1:0] read_data;

    genvar n;
    generate
        for (n = 0; n < Num_Local_Sched ; n = n + 1) begin : Flatten_Outputs
            assign Command_flat[n*6+5:n*6] = Command[n];
            assign Address1_flat[Address_Size*(n+1) - 1:n*Address_Size] = Address1[n];
            assign Address2_flat[Address_Size*(n+1) - 1:n*Address_Size] = Address2[n];
            assign Address3_flat[Address_Size*(n+1) - 1:n*Address_Size] = Address3[n];
            assign DIN_flat[(n+1)*DATA_WIDTH-1:n*DATA_WIDTH] = DIN[n];
            assign write_en_flat[n] = write_en[n];
        end
    endgenerate

    //localparam Num_Local_Sched = 1 << (Address_Size - Page_Size);

    reg [DATA_WIDTH+Address_Size+8-1:0] Combined_Command;
    wire [DATA_WIDTH+Address_Size+8-1:0] Combined_Command_ps;
    assign Combined_Command_ps = wvalid?{waddr_reg, wdata}: arvalid? {araddr, {DATA_WIDTH{1'b0}}}: 0;

    wire [5:0] Opcode;
    wire [Address_Size-1:0] Address_1;
    wire [Address_Size-1:0] Address_2;
    wire [Address_Size-1:0] Address_3;
    wire [DATA_WIDTH-1:0] RawDIN;

    wire Operation_Type_ps;
    reg Operation_Type;

//    wire [Address_Size - Page_Size - 1:0] Page_Select,Page_Select_PNM_END,Page_Select_PNM_RES;
    // assign Page_Select = Address_1[Address_Size-1:Page_Size];
    // assign Page_Select_PNM_END = Address_1[Address_Size-1:Page_Size];
    // assign Page_Select_PNM_RES = Address_1[Address_Size-1:Page_Size];
    // Page extraction
    wire [Address_Size - Page_Size - 1:0] page1_ps = Address_1[Address_Size-1:Page_Size];
    wire [Address_Size - Page_Size - 1:0] page2_ps = Address_2[Address_Size-1:Page_Size];
    wire [Address_Size - Page_Size - 1:0] page3_ps = Address_3[Address_Size-1:Page_Size];
    reg [Address_Size - Page_Size - 1:0] page1;
    reg [Address_Size - Page_Size - 1:0] page2;
    reg [Address_Size - Page_Size - 1:0] page3;

    // Span calculation
    wire [Address_Size - Page_Size - 1:0] span = (page2_ps > page1_ps) ? (page2_ps - page1_ps) : (page1_ps - page2_ps);
    wire [Address_Size - Page_Size - 1:0] res_end = ((page3_ps + span) >= Num_Local_Sched) ? Num_Local_Sched - 1 : (page3_ps + span);
    wire empty;
    
    
    always @(posedge clk) begin
        if(!rst_n) begin
            Combined_Command <= 0;
        end
        else begin
            Combined_Command <= Combined_Command_ps;
        end 
    end
 
    
    always @(posedge clk) begin
        if(!rst_n) begin
            rvalid <= 0;
            rlast <= 0;
        end
        else begin
            rvalid <= rvalid_next;
            rlast <= rlast_ps;
        end 
    end


    always @(*) begin
        rdata = read_data;
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            page1 <= 0;
            page2 <= 0;
            page3 <= 0;
            Operation_Type <= 0;
        end
        else if(wvalid || arvalid) begin
            page1 <= page1_ps;
            page2 <= page2_ps;
            page3 <= page3_ps;
            Operation_Type <= Operation_Type_ps;
        end
    end
    
    always @(posedge clk) begin
        if(!rst_n) begin
           write_ps <= 0;
        end
        else begin
            write_ps <= arvalid;
        end
    end
    
    reg aw_en;

    always @(posedge clk) begin
        if (!rst_n) begin
            awready <= 1'b0;
            wready  <= 1'b0;
            bvalid  <= 1'b0;
            bresp   <= 2'b00;
            write_count <= 0;
            waddr_reg <= 0;
        end else begin
            // Accept address and data when both valid and not already accepted
            if (awvalid && !awready && PNM_Done) begin
                awready <= 1'b1;
                waddr_reg  <= awaddr;
                write_count <= awlen;
                wburst_type <= awburst;
//                beat_size <= (1<<awsize);
                wwrap_mask_reg <= wwrap_mask;
            end else begin
                awready <= 1'b0;
            end
            
            if(wvalid && !wready) begin
                wready <= 1'b1;
                
                if(PNM_Done) begin
                case(wburst_type)
                    2'b00: waddr_reg <= waddr_reg;
                    2'b01: begin 
                        waddr_reg <= waddr_reg + (1 << awsize);
                    end
                    2'b10: waddr_reg <= waddr_reg + (1 << awsize) & wwrap_mask_reg;
                endcase
                end else begin
                    waddr_reg <= waddr_reg;
                end
                if (write_count != 0) begin
                    write_count <= write_count -1;
                end
            end
            else begin
                wready <= 1'b0;
            end
            
                        
            if (wvalid && wready && wlast && PNM_Done) begin
                bvalid <= 1'b1;
                bresp <= 2'b00;
            end 
            else if (bvalid && bready) begin
                bvalid <= 1'b0;
            end

//            // Send write response once accepted
//            if(!awvalid && !wvalid)
//                bvalid <= 1'b0;
//            else if (!bvalid && bready && awready && wready && PNM_Done) begin
//                bvalid <= 1'b1;
//                bresp  <= 2'b00; // OKAY
//            end
        end
    end

    reg ar_latch;

    always @(posedge clk) begin
        if (!rst_n) begin
            arready <= 1'b0;
            rvalid_next  <= 1'b0;
            rresp   <= 2'b00;
            ar_latch <= 0;
            rlast_ps <= 0;
            read_count <= 0;
        end else begin
        
            if(arvalid && !arready && PNM_Done) begin                
                ar_latch <= 1'b1;

                arready <= 1'b1;
                raddr_reg <= araddr;
                
                read_count <= arlen;
                rburst_type <= arburst;
//                beat_size <= (1<<awsize);
                rwrap_mask_reg <= rwrap_mask;
            end
            else begin
                arready <= 1'b0;
            end
            
            if(!rvalid_next && (read_count != 8'hFF || arlen == 0) && !empty) begin

                rvalid_next <= 1'b1;
                //rdata <= 32'hdeadbeef;
                rresp <= 2'b00;
                rlast_ps <= (read_count == 0);
                
                case(rburst_type)
                    2'b00: raddr_reg <= raddr_reg;
                    2'b01: raddr_reg <= raddr_reg + (1 << awsize);
                    2'b10: raddr_reg <= raddr_reg + (1 << arsize) && rwrap_mask_reg;
                endcase
                
                if(read_count != 0) begin
                    read_count <= read_count - 1;
                end
            end
            else if (rvalid_next && rready) begin
                rvalid_next <= 0;
                ar_latch <= 1'b0;

                if(rlast_ps) begin
                    rlast_ps <= 0;
                end
            end
//            // Accept read address
//            if (arvalid && !arready && PNM_Done) begin
//                ar_latch <= 1'b1;
//                arready <= 1'b1;
//            end else begin
//                arready <= 1'b0;
//            end

//            // Provide data (when arvalid was accepted earlier and data is ready)
//            if (!rvalid && ar_latch && !empty) begin
//                rvalid <= 1'b1;
//                rresp  <= 2'b00;
//            end else if (rvalid && rready) begin
//                rvalid <= 1'b0;
//                ar_latch <= 1'b0;
//            end
        end
    end

    // Clear outputs by default
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < Num_Local_Sched; i = i + 1) begin
                Command[i]   <= 6'd0;
                Address1[i]  <= {Page_Size{1'd0}};
                Address2[i]  <= {Page_Size{1'd0}};
                Address3[i]  <= {Page_Size{1'd0}};
                DIN[i]       <= {DATA_WIDTH{1'd0}};
                //write_en[i]  <= 1'b0;
            end
        end 
        else if ((wready) || (arready)) begin
            Command_PNM <= Opcode;
            Address1_PNM <= Address_1;
            Address2_PNM <= Address_2;
            Address3_PNM <= Address_3;
            if (Operation_Type_ps == 1'b1) begin  // PIM or PNM
//                   $display("The current pages are: (%d -> %d) and (%d->%d)", page1_ps, page2_ps, page3_ps, res_end);
                   for (i = 0; i < Num_Local_Sched; i = i + 1) begin
                //    if ((page1_ps == page2_ps) && (page2_ps == page3_ps) && (i == page1_ps)) begin
                  //      // === PIM command (same page) ===
                    //    Command[i]   <= Opcode;
                      //  Address1[i]  <= Address_1[Page_Size-1:0];
                       // Address2[i]  <= Address_2[Page_Size-1:0];
                       // Address3[i]  <= Address_3[Page_Size-1:0];
                       // DIN[i]       <= RawDIN;
//                        write_en[i]  <= bvalid||write_ps;

                     if ((i >= page1_ps && i <= page2_ps) || (i >= page3_ps && i <= res_end)) begin
                        // === PNM command (multi-page) ===
                        Command[i]   <= Opcode;
                    
                        Address1[i]  <= Address_1[Page_Size-1:0];
                        Address2[i]  <= Address_2[Page_Size-1:0];
                        Address3[i]  <= Address_3[Page_Size-1:0];
                        
                        DIN[i]       <= {DATA_WIDTH{1'd0}};
//                        write_en[i]  <= bvalid||write_ps;

                    end else begin
                        Command[i]   <= 6'd0;
                        Address1[i]  <= {Page_Size{1'd0}};
                        Address2[i]  <= {Page_Size{1'd0}};
                        Address3[i]  <= {Page_Size{1'd0}};
                        DIN[i]       <= {DATA_WIDTH{1'd0}};
//                        write_en[i]  <= 1'b0;
                    end
                    end
                end
                else begin
                    for (i = 0; i < Num_Local_Sched; i = i + 1) begin
                        if(page1_ps == i) begin
                            // === Read Write ===
                            Command[i]   <= Opcode;
                            Address1[i]  <= Address_1[Page_Size-1:0];
                            Address2[i]  <= Address_2[Page_Size-1:0];
                            Address3[i]  <= Address_3[Page_Size-1:0];
                            DIN[i]       <= RawDIN;
//                            write_en[i]  <= bvalid||write_ps;
                        end
                        else begin
                            Command[i]   <= 6'd0;
                            Address1[i]  <= {Page_Size{1'd0}};
                            Address2[i]  <= {Page_Size{1'd0}};
                            Address3[i]  <= {Page_Size{1'd0}};
                            DIN[i]       <= {DATA_WIDTH{1'd0}};
//                            write_en[i]  <= 1'b0;
                        end
                    end
                end
            end
//        else write_en <= 0;
        end
        
    always @(posedge clk) begin
     if(!rst_n) begin
        write_en <= 0;
     end
     else begin
     if (write_en != 0) write_en <= 0;
     else if (Operation_Type == 1'b1) begin  // PIM or PNM
                   for (i = 0; i < Num_Local_Sched; i = i + 1) begin
                    if ((page1_ps == page2_ps) && (page2_ps == page3_ps) && (i == page1_ps)) begin
                        // === PIM command (same page) ===
                        write_en[i]  <= bvalid||write_ps;

                    end else if ((i >= page1_ps && i <= page2_ps) || (i >= page3_ps && i <= res_end)) begin
                        // === PNM command (multi-page) ===Command[i]   <= Opcode;
                        
                        write_en[i]  <= bvalid||write_ps;

                    end else begin
                        
                        write_en[i]  <= 1'b0;
                    end
                    end
                end
                else begin
                    for (i = 0; i < Num_Local_Sched; i = i + 1) begin
                        if(page1_ps == i) begin
                            // === Read Write ===
                            
                            write_en[i]  <= bvalid||write_ps;
                        end
                        else begin
                            
                            write_en[i]  <= 1'b0;
                        end
                    end
                end
                end
    end

    // Instantiate command decoder
    Seperator i_Seperate (
        .Combined_Command(Combined_Command),
        .Enable(1'b1),  // Assuming always enabled
        .Opcode(Opcode),
        .Address_1(Address_1),
        .Address_2(Address_2),
        .Address_3(Address_3),
        .DIN(RawDIN)
    );

    OP_Type_Decoder i_OP_Type (
        .Opcode(Opcode),
        .OP_type(Operation_Type_ps)
    );

    valid_data_selector #( .WIDTH(DATA_WIDTH), .N(Num_Local_Sched)) i_dout_selector(
    .clk(clk),
    .rst_n(rst_n),
    .DOUT_flat(DOUT_flat),
    .fifo_data_in(DOUT),
    .fifo_write_en(fifo_write_en),
    .valid(DOUT_valid));

    Sched_queue #(.FIFO_WIDTH(DATA_WIDTH), .FIFO_DEPTH(256)) i_global_queue( .clk(clk), 
                                                               .rst_n(rst_n),
                                                               .write_en(fifo_write_en),
                                                               .data_in(DOUT),
                                                               .empty(empty), 
                                                               .read_en(rvalid_next&rready&!empty),
                                                               .full(buffer_full),
                                                               .data_out(read_data));

endmodule