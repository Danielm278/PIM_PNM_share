`timescale 1ns/1ps

module Sched_queue #(
    parameter FIFO_DEPTH = 16,
    parameter FIFO_WIDTH = 8
)(
    input clk,
    input rst_n,

    input write_en,
    input [FIFO_WIDTH-1:0] data_in,
    output empty,

    input read_en,
    output full,
    output reg [FIFO_WIDTH-1:0] data_out
);

    localparam PTR_WIDTH = $clog2(FIFO_DEPTH);

    // Force BRAM
    (* ram_style = "block" *) reg [FIFO_WIDTH-1:0] mem_array [0:FIFO_DEPTH-1];

    reg [PTR_WIDTH:0] read_ptr, write_ptr;
    wire [PTR_WIDTH:0] next_read_ptr, next_write_ptr;

    assign full = (read_ptr[PTR_WIDTH] ^ write_ptr[PTR_WIDTH]) &&
                  (read_ptr[PTR_WIDTH-1:0] == write_ptr[PTR_WIDTH-1:0]);

    assign empty = (read_ptr == write_ptr);

    assign next_write_ptr = (write_ptr[PTR_WIDTH-1:0] == FIFO_DEPTH - 1)
        ? {~write_ptr[PTR_WIDTH], {(PTR_WIDTH){1'b0}}}
        : write_ptr + 1;

    assign next_read_ptr = (read_ptr[PTR_WIDTH-1:0] == FIFO_DEPTH - 1)
        ? {~read_ptr[PTR_WIDTH], {(PTR_WIDTH){1'b0}}}
        : read_ptr + 1;

    // Write process
    always @(posedge clk) begin
        if (!rst_n)
            write_ptr <= 0;
        else if (write_en && !full) begin
            mem_array[write_ptr[PTR_WIDTH-1:0]] <= data_in;
            write_ptr <= next_write_ptr;
        end
    end

    // Read process
    always @(posedge clk) begin
        if (!rst_n)
            read_ptr <= 0;
        else if (read_en && !empty)
            read_ptr <= next_read_ptr;
    end

    // Registered read data (sync BRAM behavior)
    always @(posedge clk) begin
        if (read_en && !empty)
            data_out <= mem_array[read_ptr[PTR_WIDTH-1:0]];
    end

endmodule
