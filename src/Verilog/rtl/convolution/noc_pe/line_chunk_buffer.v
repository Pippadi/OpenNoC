`timescale 1ns/1ps

// line_chunk_buffer assembles incoming pixel chunks into a full line buffer.
// Chunks may arrive out of order, `chunk_avail` should be asserted for exactly
// one cycle for each chunk, and `chunk_idx` should indicate the correct position
// of the chunk within the line. When all chunks have been received, `line_valid`
// will be asserted, and `line` will contain the complete line of pixel data.
module line_chunk_buffer
#(
    parameter PIX_WIDTH = 8,
    parameter LINE_WIDTH = 16,
    parameter CHUNK_WIDTH = 4
)
(
    input rst_n,
    input clk,
    input chunk_avail,
    input [$clog2(LINE_WIDTH/CHUNK_WIDTH)-1:0] chunk_idx,
    input [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk,
    input line_clear,
    output reg [LINE_WIDTH*PIX_WIDTH-1:0] line,
    output wire line_valid
);

reg [$clog2(LINE_WIDTH/CHUNK_WIDTH)-1:0] chunks_received;
assign line_valid = chunks_received == LINE_WIDTH/CHUNK_WIDTH;

always @ (posedge clk) begin
    if (~rst_n | line_clear) begin
        line <= {(LINE_WIDTH*PIX_WIDTH){1'b0}};
        chunks_received <= 0;
    end else begin
        if (chunk_avail) begin
            line[chunk_idx*CHUNK_WIDTH +: CHUNK_WIDTH] <= chunk;
            chunks_received <= chunks_received + 1;
        end
    end
end

endmodule
