`timescale 1ns/1ps

module line_chunker
#(
    parameter PIX_WIDTH = 8,
    parameter LINE_WIDTH = 512,
    parameter CHUNK_WIDTH = 4
)
(
    input wire rst_n,
    input wire clk,
    input wire line_valid,
    input wire [LINE_WIDTH*PIX_WIDTH-1:0] line_in,
    input wire chunk_out_ready,
    output wire [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_out,
    output wire chunk_out_valid,
    output reg [$clog2(LINE_WIDTH/CHUNK_WIDTH)-1:0] chunk_idx,
    output wire complete
);

reg [1:0] state;
localparam IDLE = 2'b00, SEND_CHUNK = 2'b01, WAIT_READY = 2'b10, COMPLETE = 2'b11;

assign chunk_out = line_in[chunk_idx*CHUNK_WIDTH*PIX_WIDTH +: CHUNK_WIDTH*PIX_WIDTH];
assign chunk_out_valid = state == WAIT_READY;
assign complete = state == COMPLETE;

always @ (posedge clk) begin
    if (~rst_n) begin
        chunk_idx <= 0;
        state <= IDLE;
    end else begin
        case (state)
            IDLE: begin
                chunk_idx <= 0;
                if (line_valid)
                    state <= SEND_CHUNK;
            end
            SEND_CHUNK: state <= WAIT_READY;
            WAIT_READY: begin
                if (chunk_out_ready) begin
                    state <= chunk_idx == (LINE_WIDTH/CHUNK_WIDTH - 1) ? COMPLETE : SEND_CHUNK;
                    chunk_idx <= chunk_idx + 1;
                end
            end
            COMPLETE: state <= line_valid ? COMPLETE : IDLE;
        endcase
    end
end

endmodule
