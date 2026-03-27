`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.03.2026 08:36:04
// Design Name: 
// Module Name: reassembler
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// reassembles and stores the entire image, gives out the result on demand
module reassembler #(
    parameter IMAGE_WIDTH = 512,
    parameter IMAGE_HEIGHT = 512,
    parameter PIXEL_DEPTH = 8,
    parameter CHUNK_WIDTH = 2, // number of pixels sent by each chunk
    parameter SEG_CNT_X = 2,   // total number of segments in x and y direction
    parameter SEG_CNT_Y = 2,
    parameter MAX_CHUNK_CNT_X = 2, // within a segment
    parameter MAX_CHUNK_CNT_Y = 2,
    parameter READ_PIXEL_CNT = 4 // number of pixels read out at a time, row-wise
)(
    input wire clk, rst, chunk_avail, mode, // mode:0 for writing, 1 for reading
    input wire [CHUNK_WIDTH*PIXEL_DEPTH-1:0] chunk_in,
    input wire [$clog2(SEG_CNT_X)-1:0] seg_idx_x,
    input wire [$clog2(SEG_CNT_Y)-1:0] seg_idx_y,
    input wire [$clog2(MAX_CHUNK_CNT_X)-1:0] chunk_idx_x,
    input wire [$clog2(MAX_CHUNK_CNT_Y)-1:0] chunk_idx_y,
    output wire opReady,
    output reg [READ_PIXEL_CNT*PIXEL_DEPTH-1:0] pixel_out
);
    
    // STORES THE ENTIRE IMAGE
    reg [PIXEL_DEPTH-1:0] imageOut [IMAGE_HEIGHT*IMAGE_WIDTH-1:0];
    // A single bit to signify if a chunk is received or not
    reg [IMAGE_HEIGHT*IMAGE_WIDTH/CHUNK_WIDTH - 1:0] chunkValid;
    wire [$clog2(IMAGE_HEIGHT*IMAGE_WIDTH/CHUNK_WIDTH)+1:0] chunkAddress;
    
    // calculating chunk address
    assign chunkAddress = (seg_idx_y * MAX_CHUNK_CNT_Y + chunk_idx_y) * (SEG_CNT_X * MAX_CHUNK_CNT_X) + (seg_idx_x * MAX_CHUNK_CNT_X + chunk_idx_x);
    
    assign opReady = &chunkValid;
    
    // read index
    reg [$clog2(IMAGE_HEIGHT*IMAGE_WIDTH/READ_PIXEL_CNT)-1:0] readIndex;

    integer i;
    always @ (posedge clk) begin
        if (~mode) begin
            if (~rst) begin
                chunkValid <= 0;
            end else begin
                if (chunk_avail) begin
                    chunkValid[chunkAddress] <= 1;
            
                    for (i = 0; i < CHUNK_WIDTH; i = i + 1) begin
                        imageOut[chunkAddress*CHUNK_WIDTH + i] <= chunk_in[i*PIXEL_DEPTH +: PIXEL_DEPTH];
                    end
                end
            end
        end else begin
            if (~rst) begin
                readIndex <= 0;
            end else begin
                for (i = 0; i < READ_PIXEL_CNT; i = i + 1) begin
                    pixel_out[i*PIXEL_DEPTH +: PIXEL_DEPTH] <= imageOut[readIndex+i];
                end
                readIndex <= readIndex + READ_PIXEL_CNT;
            end
        end
    end
    
endmodule
