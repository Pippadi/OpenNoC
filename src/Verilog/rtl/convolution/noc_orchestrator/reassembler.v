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
// module reassembler_prev #(
//     parameter IMAGE_WIDTH = 512,
//     parameter IMAGE_HEIGHT = 512,
//     parameter PIXEL_DEPTH = 8,
//     parameter CHUNK_WIDTH = 2, // number of pixels sent by each chunk
//     parameter SEG_CNT_X = 2,   // total number of segments in x and y direction
//     parameter SEG_CNT_Y = 2,
//     parameter MAX_CHUNK_CNT_X = 2, // within a segment
//     parameter MAX_CHUNK_CNT_Y = 2,
//     parameter READ_PIXEL_CNT = 4 // number of pixels read out at a time, row-wise
// )(
//     input wire clk, rst, chunk_avail, mode, // mode:0 for writing, 1 for reading
//     input wire [CHUNK_WIDTH*PIXEL_DEPTH-1:0] chunk_in,
//     input wire [$clog2(SEG_CNT_X)-1:0] seg_idx_x,
//     input wire [$clog2(SEG_CNT_Y)-1:0] seg_idx_y,
//     input wire [$clog2(MAX_CHUNK_CNT_X)-1:0] chunk_idx_x,
//     input wire [$clog2(MAX_CHUNK_CNT_Y)-1:0] chunk_idx_y,
//     output wire opReady,
//     output reg [READ_PIXEL_CNT*PIXEL_DEPTH-1:0] pixel_out
// );
    
//     // STORES THE ENTIRE IMAGE
//     reg [PIXEL_DEPTH-1:0] imageOut [IMAGE_HEIGHT*IMAGE_WIDTH-1:0];
//     // A single bit to signify if a chunk is received or not
//     reg [IMAGE_HEIGHT*IMAGE_WIDTH/CHUNK_WIDTH - 1:0] chunkValid;
//     wire [$clog2(IMAGE_HEIGHT*IMAGE_WIDTH/CHUNK_WIDTH)+1:0] chunkAddress;
    
//     // calculating chunk address
//     assign chunkAddress = (seg_idx_y * MAX_CHUNK_CNT_Y + chunk_idx_y) * (SEG_CNT_X * MAX_CHUNK_CNT_X) + (seg_idx_x * MAX_CHUNK_CNT_X + chunk_idx_x);
    
//     assign opReady = &chunkValid;
    
//     // read index
//     reg [$clog2(IMAGE_HEIGHT*IMAGE_WIDTH/READ_PIXEL_CNT)-1:0] readIndex;

//     integer i;
//     always @ (posedge clk) begin
//         if (~mode) begin
//             if (~rst) begin
//                 chunkValid <= 0;
//             end else begin
//                 if (chunk_avail) begin
//                     chunkValid[chunkAddress] <= 1;
            
//                     for (i = 0; i < CHUNK_WIDTH; i = i + 1) begin
//                         imageOut[chunkAddress*CHUNK_WIDTH + i] <= chunk_in[i*PIXEL_DEPTH +: PIXEL_DEPTH];
//                     end
//                 end
//             end
//         end else begin
//             if (~rst) begin
//                 readIndex <= 0;
//             end else begin
//                 for (i = 0; i < READ_PIXEL_CNT; i = i + 1) begin
//                     pixel_out[i*PIXEL_DEPTH +: PIXEL_DEPTH] <= imageOut[readIndex+i];
//                 end
//                 readIndex <= readIndex + READ_PIXEL_CNT;
//             end
//         end
//     end
// endmodule

module reassembler
#(
    parameter PIX_WIDTH = 8,

    parameter NOC_X = 4,
    parameter NOC_Y = 2,

    parameter NOC_ADDR_X = 0,
    parameter NOC_ADDR_Y = 0,

    parameter IMG_WIDTH = 512,
    parameter IMG_HEIGHT = 512,
    parameter CHUNK_WIDTH = 6,
    parameter SEG_CNT_X = 2,
    parameter SEG_CNT_Y = 2,

    parameter KERN_X = 3,
    parameter KERN_Y = 3,

    localparam PADDING_X = KERN_X / 2,
    localparam PADDING_Y = KERN_Y / 2,

    localparam SEG_WIDTH = IMG_WIDTH / SEG_CNT_X + 2*PADDING_X,
    localparam SEG_HEIGHT = IMG_HEIGHT / SEG_CNT_Y + 2*PADDING_Y,
    localparam SEG_CNT_TOT = SEG_CNT_X * SEG_CNT_Y,

    localparam NOC_BIT_WIDTH = 2*($clog2(NOC_X)+$clog2(NOC_Y)) + $clog2(SEG_WIDTH/CHUNK_WIDTH) + CHUNK_WIDTH*PIX_WIDTH,

    // number of chunks in each segment's line
    localparam SEG_LINE_CHUNK_CNT = SEG_WIDTH / (CHUNK_WIDTH * PIXEL_WIDTH) 
)
(
    input rst_n,
    input clk,

    // AXI-stream-like interface, see section 2.2 here:
    // https://documentation-service.arm.com/static/64819f1516f0f201aa6b963c
    input wire noc_in_valid,
    // Pixel data (chunk), Chunk index, Source X, Source Y, Dest X, Dest Y
    input wire [NOC_BIT_WIDTH-1:0] noc_in_data,
    output wire noc_in_ready,

    // Interface for that PE segment map. Will be combinationally read.
    // No need to wait for clock edge.
    output reg [$clog2(NOC_X)-1:0] pe_x_idx,
    output reg [$clog2(NOC_Y)-1:0] pe_y_idx,
    // Segment number
    input [$clog2(SEG_CNT_TOT)-1:0] seg_no,
    // Line number within the segment
    input [$clog2(SEG_HEIGHT)-1:0] seg_line_no,
    // Tell the dispatcher that a full line has been received from the given
    // PE. Assert for exactly one clock cycle.
    output reg line_recvd,

    // If there's another way you'd like to do this, feel free,
    // we can offload some of the logic to the testbench right now.
    // Just need some way to get the image data back to the testbench.
    output reg [$clog2(IMG_HEIGHT)-1:0] img_line_idx,
    output reg [IMG_WIDTH*PIX_WIDTH-1:0] img_line_out,
    // Assert for one cycle, no acknowledgement needed
    output reg img_line_valid
);

    // the buffer is IMG_WIDTH wide but in Y it has only 2 SEGMENTS
    // one gets filled while the other can be thrown out in parallel
    // line_chunk_counter = counts the number of chunks received for a line in the segment
    // seg_line_counter = number of lines received for a segment
    // seg_idx_x_counter determines which of the segments in X is being filled currently
    // buffer_y_idx_coutner determines which of the Y SEGMENT ROWS is being filled currently

    localparam IMG_LINE_SIZE = IMG_WIDTH * PIX_WIDTH;
    localparam SEG_ROW_SIZE = IMG_LINE_SIZE * SEG_HEIGHT;
    localparam LINE_SIZE = SEG_WIDTH * PIX_WIDTH;

    reg [2*SEG_CNT_X*SEG_HEIGHT*SEG_WIDTH*PIX_WIDTH-1:0] buff_img;

    reg [$clog2(SEG_LINE_CHUNK_CNT)-1:0] line_chunk_counter;
    reg [$clog2(SEG_HEIGHT)-1:0] seg_line_counter;
    reg [$clog2(SEG_CNT_X)-1:0] seg_idx_x_counter;
    reg buffer_y_idx_counter; // only needs to count up to 2 because buffer only has 2 segments in Y

    reg [1:0] throw_state; // determines weather a particular lane is ready to be given as an output
    reg [$clog2(SEG_HEIGHT)-1:0] throw_line_counter; // counts the index of the line to be thrown out

    wire [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_in;
    assign chunk_in = noc_in_data[CHUNK_WIDTH*PIX_WIDTH-1:0];

    wire [$clog2(SEG_WIDTH/CHUNK_WIDTH)-1:0] chunk_idx_x;
    assign chunk_idx_x = noc_in_data[CHUNK_WIDTH*PIX_WIDTH -: $clog2(SEG_WIDTH/CHUNK_WIDTH)];

    always @(negedge rst_n) begin
        // reset all counters
        img_line_idx <= 0;
        img_line_valid <= 0;
        line_chunk_counter <= 0;
        seg_line_counter <= 0;
        seg_idx_x_counter <= 0;
        buffer_y_idx_counter <= 0;
        throw_state <= 0;
        throw_line_counter <= -1;
        img_line_idx <= -1; // when new lines are thrown out +1 to the previous value, img_line_idx will overflow and become 0, which is the index of the first line of the image
    end

    always @(posedge clk) begin
        if (rst_n && noc_in_valid) begin
            buff_img[buffer_y_idx_counter*SEG_ROW_SIZE + seg_line_counter*IMG_LINE_SIZE + seg_idx_x_counter*LINE_SIZE + chunk_idx_x*CHUNK_WIDTH*PIX_WIDTH +: CHUNK_WIDTH*PIX_WIDTH] <= chunk_in;

            // incrementing counters as needed
            // incrementing the line_chunk_counter, rolling it back to 0 when a line inside a segment has been filled
            if (line_chunk_counter == SEG_LINE_CHUNK_CNT - 1) begin
                line_chunk_counter <= 0;

                // incrementing the seg_line_counter, rolling it back to 0 when the full segment has been filled
                if (seg_line_counter == SEG_HEIGHT - 1) begin
                    seg_line_counter <= 0;

                    // incrementing the seg_idx_x_counter, rolling back to 0 and switching the lanes when the entire
                    // row of segments has been filled
                    if (seg_idx_x_counter == SEG_CNT_X - 1) begin
                        seg_idx_x_counter <= 0;
                        throw_state[buffer_y_idx_counter] <= 1; // the lane that just got filled is ready to be thrown out
                        buffer_y_idx_counter = ~buffer_y_idx_counter;
                    end else begin
                        seg_idx_x_counter <= seg_idx_x_counter + 1;
                    end
                end else begin
                    seg_line_counter <= seg_line_counter + 1;
                end
            end else begin
                line_chunk_counter <= line_chunk_counter + 1;
            end

            // output mechanism, can be done in parallel with receiving the next line
            if (&throw_state) begin
                localparam BUF_LINE_IDX = throw_state[1] * SEG_HEIGHT + throw_line_counter;
                img_line_out <= buff_img[BUF_LINE_IDX*IMG_LINE_SIZE +: IMG_LINE_SIZE];
                img_line_idx <= img_line_idx + 1;
                img_line_valid <= 1;

                if (throw_line_counter == SEG_HEIGHT - 1) begin
                    throw_line_counter <= 0;
                    throw_state[~buffer_y_idx_counter] <= 0;
                end else begin
                    throw_line_counter <= throw_line_counter + 1;
                end
            end
        end
    end
endmodule
