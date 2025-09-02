`timescale 1ns/1ps

module pim_page #(parameter DATA_WIDTH = 32, BLOCK_SIZE = 1024, NUM_EXEC = 2)(
    input clk,
    input rst_n,
    input [4:0] Sched_Command,
    output reg [NUM_EXEC-1:0] PIM_Busy,

    input [DATA_WIDTH-1:0] From_PNM,
    input PNM_Data_Ready,
    output reg [DATA_WIDTH-1:0] To_PNM,
    input [$clog2(BLOCK_SIZE)-1:0] PNM_In_Addr, PNM_Res_Addr,

    input [$clog2(BLOCK_SIZE)-1:0] Address_1,
    input [$clog2(BLOCK_SIZE)-1:0] Address_2,
    input [$clog2(BLOCK_SIZE)-1:0] Address_3,

    input [DATA_WIDTH-1:0] DIN,
    output reg [DATA_WIDTH-1:0] DOUT,
    output reg DOUT_valid,

    // DMA Interface
    input         dma_en,
    input [$clog2(BLOCK_SIZE)-1:0]  dma_addr,
    input         dma_we,
    input [DATA_WIDTH-1:0] dma_din,
    output reg [DATA_WIDTH-1:0] dma_dout,
    output reg        dma_busy,
    output PNM_enable
);

localparam PTR_WIDTH = $clog2(BLOCK_SIZE);

// Declare three separate memory arrays, each intended for BRAM inference.
// Each will have its own independent read/write ports.
(* ram_style = "block" *) reg [DATA_WIDTH -1:0] mem_bank_array_main      [BLOCK_SIZE-1:0];
(* ram_style = "block" *) reg [DATA_WIDTH -1:0] mem_bank_array_pim_read1 [BLOCK_SIZE-1:0];
(* ram_style = "block" *) reg [DATA_WIDTH -1:0] mem_bank_array_pim_read2 [BLOCK_SIZE-1:0];


wire PIM_enable, mem_wenable, mem_renable;

reg [PTR_WIDTH-1:0] PIM_busy_address [NUM_EXEC-1:0];
reg [4:0] ALU_Command [NUM_EXEC-1:0];
wire [NUM_EXEC-1:0] results_valid;

reg [DATA_WIDTH-1:0] data_1 [NUM_EXEC-1:0];
reg [DATA_WIDTH-1:0] data_2 [NUM_EXEC-1:0];
wire [DATA_WIDTH-1:0] result [NUM_EXEC-1:0];

reg [PTR_WIDTH-1:0] Addr_3_lock [NUM_EXEC-1:0];
reg [NUM_EXEC-1:0] finished_PIM_CALC;
reg data_ready;

wire [NUM_EXEC-1:0] next_PIM;
reg [NUM_EXEC-1:0] curr_PIM;
reg found; // This 'found' signal is not strictly necessary for BRAM inference,
           // but was in your previous code to prioritize PIM writebacks.

reg command_taken;
integer i, j;

// Internal signals for consolidated memory write operation (to all three memories)
reg mem_write_en_all;
reg [PTR_WIDTH-1:0] mem_write_addr_all;
reg [DATA_WIDTH-1:0] mem_write_data_all;

// Internal signals for consolidated read operation from mem_bank_array_main
reg mem_read_en_main;
reg [PTR_WIDTH-1:0] mem_read_addr_main;
reg [DATA_WIDTH-1:0] mem_read_data_main_reg; // Registered output from main RAM

assign mem_wenable = ~Sched_Command[4] & (~Sched_Command[3]) & Sched_Command[0];
assign mem_renable = ~Sched_Command[4] & Sched_Command[3];
assign PIM_enable = Sched_Command[4] & ~Sched_Command[3];
assign PNM_enable = Sched_Command[4] & Sched_Command[3];

assign next_PIM = (curr_PIM < NUM_EXEC-1)? curr_PIM + 1: 0;


// Combinatorial logic to determine the active memory write operation
// This logic determines the single write transaction that will be applied to ALL memory instances
always @* begin
    mem_write_en_all   = 1'b0;
    mem_write_addr_all = 0; // Use '0' instead of 0 for clarity in Verilog-2001+
    mem_write_data_all = 0;
    found = 1'b0; // Initialize found

    // Prioritize writes: DMA > PNM > General > PIM
    if (dma_en && dma_we) begin // DMA Write
        if (check_addr(dma_addr) == 2'b11 || check_addr(dma_addr) == 2'b01) begin
            mem_write_en_all   = 1'b1;
            mem_write_addr_all = dma_addr;
            mem_write_data_all = dma_din;
        end
    end else if (PNM_enable && PNM_Data_Ready) begin // PNM Writeback
        mem_write_en_all   = 1'b1;
        mem_write_addr_all = PNM_Res_Addr;
        mem_write_data_all = From_PNM;
    end else if (mem_wenable) begin // General Memory Write
        if (check_addr(Address_1) > 2'b00) begin
            mem_write_en_all   = 1'b1;
            mem_write_addr_all = Address_1;
            mem_write_data_all = DIN;
        end
    end else begin // PIM Writeback (arbitrated if NUM_EXEC > 1)
        for (j = 0; j < NUM_EXEC; j = j + 1) begin
            // Ensure only one PIM writeback happens per cycle if multiple are ready
            if (ALU_Command[j][4:3] == 2'b10 && !finished_PIM_CALC[j] && results_valid[j] && !found) begin
                mem_write_en_all   = 1'b1;
                mem_write_addr_all = Addr_3_lock[j];
                mem_write_data_all = result[j];
                found = 1'b1; // Mark as found to prevent other PIM writes in this cycle
            end
        end
    end
end

// Combinatorial logic to determine the active read operation for mem_bank_array_main
// This consolidates the read address and enable for the main memory's single read port
always @* begin
    mem_read_en_main   = 1'b0; // Default to no read
    mem_read_addr_main = 0;   // Default address

    // Prioritize reads for main outputs: DMA > PNM > General
    if (dma_en && !dma_we) begin // DMA Read
        mem_read_en_main   = 1'b1;
        mem_read_addr_main = dma_addr;
    end else if (PNM_enable) begin // PNM Read
        mem_read_en_main   = 1'b1;
        mem_read_addr_main = PNM_In_Addr;
    end else if (mem_renable) begin // General Memory Read
        mem_read_en_main   = 1'b1;
        mem_read_addr_main = Address_1;
    end
end

// Memory Access (Sequential Block)
always @(posedge clk) begin
    if (!rst_n) begin
        dma_dout        <= {DATA_WIDTH{1'b0}};
        dma_busy        <= 1'b0;
        DOUT          <= {DATA_WIDTH{1'bx}};
        finished_PIM_CALC <= 0;
        To_PNM          <= {DATA_WIDTH{1'b0}};
        mem_read_data_main_reg <= {DATA_WIDTH{1'bx}}; // Initialize registered output
        DOUT_valid <= 1'b0;
    end else begin
        // Handle dma_busy separately
        if (!dma_en) begin
            dma_busy <= 1'b0;
        end else if (dma_en && (dma_we || !dma_we)) begin // DMA active
            dma_busy <= 1'b1;
        end

        // ------------------------------------
        // Write to ALL memory instances simultaneously for coherence
        // This is a single write port for each BRAM.
        // ------------------------------------
        if (mem_write_en_all) begin
            mem_bank_array_main[mem_write_addr_all]      <= mem_write_data_all;
            mem_bank_array_pim_read1[mem_write_addr_all] <= mem_write_data_all;
            mem_bank_array_pim_read2[mem_write_addr_all] <= mem_write_data_all;
        end

        // ------------------------------------
        // Read from mem_bank_array_main into a single registered output
        // This explicitly models the registered output of a BRAM.
        // ------------------------------------
        if (mem_read_en_main) begin
            mem_read_data_main_reg <= mem_bank_array_main[mem_read_addr_main];
            if(!PNM_enable) data_ready <= 1;
        end else begin
            // Maintain the value or set to default if no read is active
            // Setting to 'bx' can sometimes help with X-propagation in simulation
            // but might not be strictly necessary for synthesis.
            mem_read_data_main_reg <= {DATA_WIDTH{1'bx}};
            data_ready <= 0;
        end

        // ------------------------------------
        // Assign registered read data to appropriate output ports
        // This is where the 1-cycle latency for main reads will be observed.
        // ------------------------------------
        if (dma_en && !dma_we) begin // DMA Read
            if (check_addr(dma_addr) == 2'b11)
                dma_dout <= mem_read_data_main_reg; // Assign from registered output
            else
                dma_dout <= 32'hABAD1DEA;
        end else if (PNM_enable) begin // PNM Read
            if (check_addr(PNM_In_Addr) > 2'b10)
                To_PNM <= mem_read_data_main_reg; // Assign from registered output
            else
                To_PNM <= {DATA_WIDTH{1'bx}};
        end else if (data_ready) begin // General Memory Read
            if (check_addr(Address_1) > 2'b01) begin
                DOUT <= mem_read_data_main_reg; // Assign from registered output
                DOUT_valid <= 1'b1;
                end
            else
                DOUT <= {DATA_WIDTH{1'bx}};
        end else begin
            DOUT <= {DATA_WIDTH{1'bx}};
            To_PNM <= {DATA_WIDTH{1'b0}}; // Default for PNM output
        end
        
        if(!data_ready) DOUT_valid <= 1'b0;

        // ------------------------------------
        // PIM Fetching Logic - Reads from dedicated PIM read memories
        // These are separate BRAMs, so concurrent reads are fine.
        // ------------------------------------
        if (PIM_enable && !command_taken) begin
            if (check_addr(Address_1) == 2'b11 && check_addr(Address_2) == 2'b11 &&
                check_addr(Address_3) != 2'b00 && check_addr(Address_3) != 2'b10) begin
                data_1[curr_PIM] <= mem_bank_array_pim_read1[Address_1]; // Read from dedicated PIM read1 memory
                data_2[curr_PIM] <= mem_bank_array_pim_read2[Address_2]; // Read from dedicated PIM read2 memory
                finished_PIM_CALC[curr_PIM] <= 1'b0;
            end
        end
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        curr_PIM <= 2'b00;
        PIM_Busy <= {NUM_EXEC{1'b0}};
        for (i = 0; i < NUM_EXEC; i = i +1) begin
            ALU_Command[i] <= 0;
        end
        command_taken <= 0;
    end else begin
        if (PIM_enable && !command_taken) begin
            if (check_addr(Address_1) == 2'b11 && check_addr(Address_2) == 2'b11 &&
                check_addr(Address_3) != 2'b00 && check_addr(Address_3) != 2'b10) begin

                curr_PIM <= next_PIM;
                Addr_3_lock[curr_PIM] <= Address_3;
                ALU_Command[curr_PIM] <= Sched_Command;

                PIM_busy_address[curr_PIM] <= Address_3;
                PIM_Busy[curr_PIM] <= 1;

                command_taken <= 1;
            end
        end else if (!PIM_enable)
            command_taken <= 0;

        for (i = 0; i < NUM_EXEC; i = i + 1) begin
            //if (ALU_Command[i][4:3] == 2'b10) begin
                if (results_valid[i]) begin
                    ALU_Command[i] <= 5'h00;
                    PIM_busy_address[i] <= {DATA_WIDTH{1'bx}};
                    Addr_3_lock[i] <= {PTR_WIDTH{1'bx}};
                    PIM_Busy[i] <= 0;
                end
            //end
        end
    end
end

function [1:0] check_addr;
    input [$clog2(BLOCK_SIZE)-1:0] Address;
    integer i;
    integer flag;
    begin
        flag = 0;
        if (Address >= BLOCK_SIZE)
            check_addr = 2'd0; // Out of bounds
        else begin
            for (i = 0; i < NUM_EXEC; i = i + 1) begin
                if (Address == PIM_busy_address[i]) begin
                    check_addr = 2'd2; // Address is busy
                    flag = 1;
                end
            end
            if(!flag) check_addr = 2'd3; // Address is valid and not busy
        end
    end
endfunction

genvar p;
generate
    for( p = 0; p < NUM_EXEC; p = p + 1) begin : pim_executors
        pim_exec i_PIM_EXEC (.clk(clk), .rst_n(rst_n),.ALU_Command(ALU_Command[p]), .data1(data_1[p]), .data2(data_2[p]), .result(result[p]), .result_valid(results_valid[p]));
    end
endgenerate

endmodule
