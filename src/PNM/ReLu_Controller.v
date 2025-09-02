`timescale 1ns/1ps
module ReLu_Controller #(parameter DATA_WIDTH = 32, Address_Size = 16, NUM_PAGES = 64) (
    input clk,
    input rst_n,

    output reg done_Relu,

    input ReLu_En,
    input ReLu_Start,
    input [Address_Size-1:0] Start_Addr,
    input [Address_Size-1:0] End_Addr,
    output reg [Address_Size-1:0] Curr_Address_Read,
    output reg [Address_Size-1:0] Curr_Address_Write,
    input [Address_Size-1:0] Result_Address,
    input [DATA_WIDTH*NUM_PAGES-1:0] DIN_All,    // Input bus containing all values
    output reg [DATA_WIDTH-1:0] DOUT,
    output DOUT_Valid);

    // State machine local parameters
    localparam IDLE    = 2'b00;
    localparam INIT    = 2'b01;
    localparam EXEC    = 2'b10;
    localparam RESULTS = 2'b11;

    // Internal signals for ReLu operation
    reg [DATA_WIDTH-1:0] ReLu_In;
    wire [DATA_WIDTH-1:0] ReLu_Out;
    integer start_up;

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

    // State machine registers
    reg [1:0] State_ReLu, Next_State_ReLu;

    wire [15:0] num_elements = (End_Addr-Start_Addr +1);

    // Next read address calculation
    wire [Address_Size-1:0] Next_Curr_Address;
    assign Next_Curr_Address = (Curr_Address_Read < End_Addr)? Curr_Address_Read + 1: Curr_Address_Read;

    // DOUT_Valid signal - always high in this design
    assign DOUT_Valid = (Curr_Address_Write >= Result_Address && start_up >= 3)?1'b1: 1'b0;

    // ReLu State Machine - State Transition Logic (Combinational)
    always @(*) begin
        done_Relu = 1'b1;
        case (State_ReLu)
            IDLE: begin
                done_Relu = 1'b1;
                if (ReLu_Start) Next_State_ReLu = INIT;
                else Next_State_ReLu = IDLE;
            end
            INIT: begin 
                done_Relu = 1'b0;
                if(ReLu_En) begin
                    Next_State_ReLu = EXEC;
                end
                else Next_State_ReLu = INIT;
            end
            EXEC: begin
                done_Relu = 1'b0;
                if (Curr_Address_Write == Result_Address + num_elements-2) Next_State_ReLu = RESULTS;
                else Next_State_ReLu = EXEC;
            end
            RESULTS: begin
                done_Relu = 1'b1;
                Next_State_ReLu = IDLE;
            end
            default: Next_State_ReLu = IDLE; // Default to IDLE for undefined states
        endcase
    end

    // ReLu State Machine - State Register (Sequential)
    always @(posedge clk) begin
        if (!rst_n) begin
            State_ReLu <= IDLE;
        end
        else begin
            State_ReLu <= Next_State_ReLu;
        end
    end

    // ReLu State Machine - Output Logic (Sequential)
    always @(posedge clk) begin
        if (!rst_n) begin
            //done_Relu <= 1'b1;                          // Assert done on reset
            Curr_Address_Read <= {Address_Size{1'b0}};  // Reset read address
            Curr_Address_Write <= {Address_Size{1'b0}}; // Reset write address
            start_up <= 0;
        end
        else begin // Only update on clock edge when not in reset
            case (State_ReLu)
                IDLE: begin
                   // done_Relu <= 1'b1;
                    Curr_Address_Read <= Start_Addr;     // Initialize read address
                    Curr_Address_Write <= Result_Address - 4; // Prepare for first write at Result_Address
                    start_up <= 0;
                end
                INIT: begin
                    Curr_Address_Read <= Start_Addr;     // Initialize read address
                    Curr_Address_Write <= Result_Address - 4; // Prepare for first write at Result_Address
                end
                EXEC: begin
                    if (start_up <= 3)
                        start_up <= start_up + 1;
                    else begin
                    Curr_Address_Write <= Curr_Address_Write + 1; // Increment write address for next result
                    //done_Relu <= 1'b0;                           // De-assert done during execution
                    Curr_Address_Read <= Next_Curr_Address;      // Move to next read address
                    if (start_up <= 4)
                        start_up <= start_up + 1;
                    else ReLu_In <= DIN; // Provide current input data to ReLu module
                    DOUT <= ReLu_Out;                            // Output the result from ReLu
                    end
                end
                RESULTS: begin
                    DOUT <= ReLu_Out;                            // Ensure final ReLu result is outputted
                   // done_Relu <= 1'b1;                           // Assert done when results are ready
                end
                default: begin
                    Curr_Address_Read <= {Address_Size{1'bx}};  // X for don't care during unexpected states
                    Curr_Address_Write <= {Address_Size{1'bx}};
                end
            endcase
        end
    end

    // Instantiate the ReLu module
    ReLu i_relu (.in_val(ReLu_In), .out_val(ReLu_Out));

endmodule
