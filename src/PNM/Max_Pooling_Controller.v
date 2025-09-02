module Max_Pooling_Controller  #(parameter DATA_WIDTH = 32, Address_Size = 16, NUM_PAGES = 64) (
    input clk,
    input rst_n,
    output  done_Max_Pool,
    input Max_Pooling_En,
    input Max_Pooling_Start,
    input [Address_Size-1:0] Start_Addr,
    input [Address_Size-1:0] End_Addr,
    input [Address_Size-1:0] Result_Address,
    output reg [Address_Size-1:0] Curr_Address_Read,
    output reg [Address_Size-1:0] Curr_Address_Write, // Current address for memory access
    input [DATA_WIDTH*NUM_PAGES-1:0] DIN_All,
    output reg [DATA_WIDTH-1:0] DOUT,
    output wire DOUT_Valid
);
    // --- Dynamic Data Selection Logic ---
    // Calculate the number of bits required to represent NUM_PAGES.
    // This is a constant value as NUM_PAGES is a parameter.
    localparam PAGE_ADDR_BITS = $clog2(NUM_PAGES);

    // Extract the 'page' index from the most significant bits of Curr_Address_Read.
    // This assumes the MSBs of the address determine which page (device) the data belongs to.
    wire [PAGE_ADDR_BITS-1:0] current_page_index;
    assign current_page_index = Curr_Address_Read[Address_Size-1 : Address_Size - PAGE_ADDR_BITS];

    // Calculate the base bit address within the `DIN_All` bus for the selected page's data.
    // This address determines where the relevant `DATA_WIDTH` chunk starts.
    // The width of this wire must be large enough to hold the maximum possible bit index.
    wire [($clog2(DATA_WIDTH * NUM_PAGES)) - 1 : 0] DIN_Base_Address;
    assign DIN_Base_Address = current_page_index * DATA_WIDTH;

    // Select the `DATA_WIDTH` slice from `DIN_All` using an indexed part-select.
    // `DIN_All[DIN_Base_Address +: DATA_WIDTH]` is the correct and synthesizable way
    // to dynamically select a `DATA_WIDTH`-wide segment starting from `DIN_Base_Address`.
    wire [DATA_WIDTH-1:0] DIN;
    assign DIN = DIN_All[DIN_Base_Address +: DATA_WIDTH];
    // --- End of Dynamic Data Selection Logic ---

    localparam IDLE         = 3'b00;   
    localparam INIT         = 3'b100;
    localparam POOL_FETCH   = 3'b01;
    localparam EXEC         = 3'b10;
    localparam RESULTS      = 3'b11;

    reg [2:0] State_Max_Pool, Next_State_Max_Pool;
    wire [Address_Size-1:0] Num_Mat_Elements;
    reg [7:0] Matrix_Size;

    reg [Address_Size-1:0] Next_Curr_Address, Next_Curr_Address_Write;

    wire [Address_Size-1:0] Next_New_Row;
    reg [Address_Size-1:0] New_Row;

    reg [DATA_WIDTH-1:0] Max_Pool_In [3:0]; // Stores the 4 inputs
    wire [DATA_WIDTH-1:0] Max_Pool_Out; // Output from fp_max_pool_2x2

    reg [7:0] exec_counter;
    reg [2:0] start_up;

    reg [2:0] counter;
    reg [31:0] Max_Pool_In_ps;

    always @(posedge clk) begin
        if(State_Max_Pool == IDLE) exec_counter <= 0;
        else if (DOUT_Valid) exec_counter <= exec_counter + 1;
    end

    //assign counter = (Curr_Address_Read-Start_Addr);

    assign Num_Mat_Elements = End_Addr - Start_Addr + 1;
    assign Next_New_Row = New_Row + 2*Matrix_Size;
    assign done_Max_Pool = (State_Max_Pool == IDLE)? 1'b1:  1'b0;
    assign DOUT_Valid = ((State_Max_Pool == POOL_FETCH || State_Max_Pool == RESULTS) && counter == 3'h0 && Curr_Address_Read > Start_Addr+1)? 1'b1: 1'b0;

    always @(posedge clk) begin
        if (State_Max_Pool == INIT ) begin
             New_Row <= Start_Addr + Matrix_Size*2 - 1;
        end
        else if (Curr_Address_Read == New_Row) begin
            New_Row <= Next_New_Row;
        end

    end

    always @(*) begin
        Next_Curr_Address_Write = Curr_Address_Write+1;
        Next_Curr_Address = Curr_Address_Read;

        case(counter)
        2'b00: begin
            Next_Curr_Address = Curr_Address_Read + 1;
        end
        2'b01:begin
            Next_Curr_Address = Curr_Address_Read + Matrix_Size - 1;
        end
        2'b10:begin
            Next_Curr_Address = Curr_Address_Read + 1;
        end
        2'b11:begin
            if (Curr_Address_Read == New_Row) Next_Curr_Address = Curr_Address_Read + 1;
            else Next_Curr_Address = Curr_Address_Read - Matrix_Size + 1;
        end
        default: ;
        endcase
    end

    // State transition logic
    always @(*) begin
        Next_State_Max_Pool = State_Max_Pool; // Default to self-loop
        Max_Pool_In_ps = Max_Pool_In[counter];

        case (State_Max_Pool)
            IDLE:
                if (Max_Pooling_Start) // Ensure Matrix_Size is valid for 2x2 pooling
                    Next_State_Max_Pool = INIT;
                else
                    Next_State_Max_Pool = IDLE;
            INIT: begin
                if(Num_Mat_Elements < 4) Next_State_Max_Pool = IDLE;
                else if (Max_Pooling_En) Next_State_Max_Pool = POOL_FETCH;

            end
            POOL_FETCH: begin
                if (counter == 3'b101) // All 4 inputs for current block are sampled
                    Next_State_Max_Pool = EXEC;
                else
                    Next_State_Max_Pool = POOL_FETCH;
            end
            EXEC:
                // Check if this is the last 2x2 block in the matrix
                if (exec_counter >= (Num_Mat_Elements>>2)-1)
                    Next_State_Max_Pool = RESULTS;
                else
                    Next_State_Max_Pool = POOL_FETCH; // Move to fetch next block

            RESULTS:
                Next_State_Max_Pool = IDLE;

            default:
                Next_State_Max_Pool = IDLE;
        endcase
    end

    // State update
    always @(posedge clk) begin
        if (!rst_n)
            State_Max_Pool <= IDLE;
        else
            State_Max_Pool <= Next_State_Max_Pool;
    end

    // Main FSM behavior and address/counter updates
    always @(posedge clk) begin
        if (!rst_n) begin
            Curr_Address_Read        <= 0;
            Curr_Address_Write       <= 0;
            //done_Max_Pool          <= 0;
            counter                  <= 0;
            Matrix_Size              <= 0;
            //DOUT_Valid               <= 0;
            DOUT                     <= 0;
            //start_up                 <= 0;
        end
        else begin
            case (State_Max_Pool)
                IDLE: begin
                    //done_Max_Pool       <= 0;
                    counter             <= 0;
                    Matrix_Size         <= sqrt_lookup(Num_Mat_Elements);

                    // The very first address to fetch for the first block
                    Curr_Address_Read        <= Start_Addr; 
                    Curr_Address_Write       <= Result_Address-1;
                    start_up <= 0;
                end
                INIT: begin
                    //done_Max_Pool       <= 0;
                    counter             <= 0;
                    Matrix_Size         <= sqrt_lookup(Num_Mat_Elements);

                    // The very first address to fetch for the first block
                    Curr_Address_Read        <= Start_Addr; 
                    Curr_Address_Write       <= Result_Address-1;
                    start_up <= 0;
                end

                POOL_FETCH: begin

                    //Curr_Address_Write       <= Next_Curr_Address_Write;
                    //DOUT_Valid <= 0; // Ensure DOUT_Valid is low during fetching
                    
                    counter              <= counter + 1; // Increment for next input

                   // if(start_up > 3) begin
                        Curr_Address_Read <= Next_Curr_Address;

                        if(start_up > 1) begin
                            Max_Pool_In[counter-2] <= DIN; // Sample the current DIN
                        end else start_up <= start_up + 1;
                    //end
                   // else begin
                   //     start_up <= start_up + 1;
                   // end
                    
                end

                EXEC: begin
                    Curr_Address_Write       <= Next_Curr_Address_Write;
                    counter <= 0; // Reset counter for the next 2x2 block
                    DOUT    <= Max_Pool_Out; // Output the result
                    //DOUT_Valid <= (Curr_Address_Write >= Result_Address); // Signal valid output
                    
                    start_up <= 0;
                    // Set Curr_Address to the start of the *first* element of the *next* 2x2 block
                    //Curr_Address <= Next_Curr_Address;
                    //done_Max_Pool <= 1;
                    //Curr_Address_Read <= Next_Curr_Address;

                end

                RESULTS: begin
                    //done_Max_Pool <= 1; // Signal operation complete
                    //DOUT_Valid    <= 0; // No valid output after done
                    //exec_counter <= 0;
                end

                default: Curr_Address_Read <= 16'hxxxx;
            endcase
        end
    end

    // Square root lookup (as before)
    function [7:0] sqrt_lookup;
        input [15:0] value;
        begin
            case (value)
                16'd1:    sqrt_lookup = 8'd1;
                16'd4:    sqrt_lookup = 8'd2;
                16'd9:    sqrt_lookup = 8'd3;
                16'd16:   sqrt_lookup = 8'd4;
                16'd25:   sqrt_lookup = 8'd5;
                16'd36:   sqrt_lookup = 8'd6;
                16'd49:   sqrt_lookup = 8'd7;
                16'd64:   sqrt_lookup = 8'd8;
                16'd81:   sqrt_lookup = 8'd9;
                16'd100:  sqrt_lookup = 8'd10;
                16'd121:  sqrt_lookup = 8'd11;
                16'd144:  sqrt_lookup = 8'd12;
                16'd169:  sqrt_lookup = 8'd13;
                16'd196:  sqrt_lookup = 8'd14;
                16'd225:  sqrt_lookup = 8'd15;
                16'd256:  sqrt_lookup = 8'd16;
                16'd289:  sqrt_lookup = 8'd17;
                16'd324:  sqrt_lookup = 8'd18;
                16'd361:  sqrt_lookup = 8'd19;
                16'd400:  sqrt_lookup = 8'd20;
                16'd441:  sqrt_lookup = 8'd21;
                16'd484:  sqrt_lookup = 8'd22;
                16'd529:  sqrt_lookup = 8'd23;
                16'd576:  sqrt_lookup = 8'd24;
                default:  sqrt_lookup = 8'd0; // Handle invalid sizes gracefully
            endcase
        end
    endfunction

    // Max pooling unit instantiation (as before)
    fp_max_pool_2x2 i_fp_max_pool (
        .in0(Max_Pool_In[0]), .in1(Max_Pool_In[1]),
        .in2(Max_Pool_In[2]), .in3(Max_Pool_In[3]),
        .out(Max_Pool_Out)
    );

endmodule
