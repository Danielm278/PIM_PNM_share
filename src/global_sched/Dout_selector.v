`timescale 1ns/1ps

module valid_data_selector #(
    parameter WIDTH = 8,
    parameter N = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire [WIDTH*N-1:0] DOUT_flat,
    output reg  [WIDTH-1:0] fifo_data_in,
    output reg              fifo_write_en,
    input [N-1:0] valid
);

    wire [WIDTH-1:0] DOUT [0:N-1];

    genvar d;
    generate
        for( d = 0; d < N; d = d+1) begin
            assign DOUT[d] = DOUT_flat[WIDTH*(d+1)-1: WIDTH*d];
        end
    endgenerate

    reg [WIDTH-1:0] selected_data;
    reg             data_valid;
    integer i;

    // Combinational block to select valid data
    always @(*) begin
        selected_data = {WIDTH{1'b0}};
        data_valid = 1'b0;

        for (i = 0; i < N; i = i + 1) begin
            // Check if DOUT[i] does not contain any X
            if (valid[i]) begin
                if (!data_valid) begin
                    selected_data = DOUT[i];
                    data_valid = 1'b1;
                end
            end
        end
    end

    // Sequential block to drive FIFO
    always @(posedge clk) begin
        if (!rst_n) begin
            fifo_data_in  <= {WIDTH{1'b0}};
            fifo_write_en <= 1'b0;
        end else begin
            fifo_data_in  <= selected_data;
            fifo_write_en <= data_valid;
        end
    end

endmodule