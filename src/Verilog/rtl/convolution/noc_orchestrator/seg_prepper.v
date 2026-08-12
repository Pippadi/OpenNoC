`timescale 1ns / 1ps

module seg_prepper
#(
    parameter PIX_WIDTH = 8,

    parameter IMG_WIDTH = 512,
    parameter IMG_HEIGHT = 512,
    parameter SEG_CNT_X = 2,
    parameter SEG_CNT_Y = 2,

    parameter KERN_X = 3,
    parameter KERN_Y = 3,

    localparam PADDING_X = (KERN_X / 2) * 2,
    localparam PADDING_Y = (KERN_Y / 2) * 2,

    localparam SEG_WIDTH = IMG_WIDTH / SEG_CNT_X + 2*PADDING_X,
    localparam SEG_HEIGHT = IMG_HEIGHT / SEG_CNT_Y + 2*PADDING_Y,
    localparam SEG_CNT_TOT = SEG_CNT_X * SEG_CNT_Y,
    localparam SEG_W_NOPAD = IMG_WIDTH / SEG_CNT_X
)
(
    input wire rst_n,
    input wire clk,

    input wire [$clog2(SEG_CNT_TOT)-1:0] pe_seg,
    input wire [$clog2(SEG_HEIGHT)-1:0] pe_seg_line_no,

    output reg img_line_in_ready,
    output reg [$clog2(SEG_CNT_X * IMG_HEIGHT)-1:0] img_line_in_idx,
    input wire [SEG_W_NOPAD*PIX_WIDTH-1:0] img_line_in,
    input wire img_line_in_valid,

    input wire segment_line_ready,
    output reg [SEG_WIDTH*PIX_WIDTH-1:0] segment_line,
    output reg segment_line_valid
);

wire [$clog2(SEG_CNT_X)-1:0] seg_idx_x = pe_seg % SEG_CNT_X;

reg [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0] this_img_line, next_img_line, prev_img_line;

// Offset within segment + (Y component of segment * segment height)
wire [$clog2(IMG_HEIGHT)-1:0] line_idx_y = pe_seg_line_no + ((pe_seg / SEG_CNT_X) * (IMG_HEIGHT/SEG_CNT_Y));
// (Y line number * No. of X segments) + X component of segment
wire [$clog2(SEG_CNT_X*IMG_HEIGHT)-1:0] this_line_idx = line_idx_y * SEG_CNT_X + seg_idx_x;

// If the line number within the segment is 0, and the segment is at the top of
// the image, or the segment line number is the bottommost, and the segment is
// along the bottom of the image, the line must be zero (zero padding).
wire line_is_top_bottom =
(pe_seg / SEG_CNT_X == 0 && pe_seg_line_no < PADDING_X) ||
(pe_seg / SEG_CNT_X == SEG_CNT_Y-1 && pe_seg_line_no > SEG_HEIGHT-PADDING_Y);


always @ (*) begin
    if (line_is_top_bottom) begin
        segment_line = {SEG_WIDTH{{PIX_WIDTH{1'b0}}}};
    end else begin
        segment_line[PIX_WIDTH*PADDING_X +: PIX_WIDTH*SEG_W_NOPAD] = this_img_line; // Main segment pixels
        if (seg_idx_x == 0)
            segment_line[PADDING_X*PIX_WIDTH-1:0] = 0; // Right halo
        else
            segment_line[PADDING_X*PIX_WIDTH-1:0] = prev_img_line[SEG_W_NOPAD*PIX_WIDTH-1 -: PIX_WIDTH*PADDING_X]; // Right halo from previous segment
        if (seg_idx_x == SEG_CNT_X - 1)
            segment_line[SEG_WIDTH*PIX_WIDTH-1 -: PIX_WIDTH*PADDING_X] = 0; // Left halo
        else
            segment_line[SEG_WIDTH*PIX_WIDTH-1 -: PIX_WIDTH*PADDING_X] = next_img_line[0 +: PIX_WIDTH*PADDING_X]; // Left halo from next segment
    end
end

reg [2:0] state;
localparam IDLE = 3'b000, READ_THIS_LINE=3'b001, READ_PREV_LINE=3'b010, READ_NEXT_LINE=3'b011, DONE=3'b100;

always @ (posedge clk) begin
    if (~rst_n) begin
        state <= 0;
        segment_line_valid <= 0;
        img_line_in_ready <= 0;
        img_line_in_idx <= 0;
        this_img_line <= {((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH){1'b0}};
        prev_img_line <= {((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH){1'b0}};
        next_img_line <= {((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH){1'b0}};
    end else begin
        case (state)
            IDLE: begin
                segment_line_valid <= 0;
                if (segment_line_ready) begin
                    state <= line_is_top_bottom ? DONE : READ_THIS_LINE;
                end
            end
            READ_THIS_LINE: begin
                img_line_in_idx <= this_line_idx;
                if (img_line_in_valid & img_line_in_ready) begin
                    this_img_line <= img_line_in;
                    state <= READ_PREV_LINE;
                    img_line_in_ready <= 0;
                end else
                    img_line_in_ready <= 1;
            end
            READ_PREV_LINE: begin
                img_line_in_idx <= this_line_idx - 1;
                if (img_line_in_valid & img_line_in_ready) begin
                    prev_img_line <= img_line_in;
                    state <= READ_NEXT_LINE;
                    img_line_in_ready <= 0;
                end else
                    img_line_in_ready <= 1;
            end
            READ_NEXT_LINE: begin
                img_line_in_idx <= this_line_idx + 1;
                if (img_line_in_valid & img_line_in_ready) begin
                    next_img_line <= img_line_in;
                    state <= DONE;
                    img_line_in_ready <= 0;
                end else
                    img_line_in_ready <= 1;
            end
            DONE: begin
                segment_line_valid <= 1;
                state <= segment_line_ready ? DONE : IDLE;
            end
            default: state <= IDLE;
        endcase
    end
end

//initial $monitor("%h %d %d", segment_line, segment_line_valid, img_line_in_idx);

endmodule
