`timescale 1ns / 1ps

module conv_dispatcher
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

    localparam NOC_BIT_WIDTH = 2*($clog2(NOC_X)+$clog2(NOC_Y)) + $clog2(SEG_WIDTH/CHUNK_WIDTH) + CHUNK_WIDTH*PIX_WIDTH
)
(
    input rst_n,
    input clk,

    output reg [$clog2(IMG_HEIGHT)-1:0] img_line_idx,
    input [IMG_WIDTH*PIX_WIDTH-1:0] img_line_in,

    // --- PE info interface ---
    output reg [$clog2(NOC_X)-1:0] pe_idx_x,
    output reg [$clog2(NOC_Y)-1:0] pe_idx_y,

    input wire pe_busy,
    input wire [$clog2(SEG_CNT_TOT)-1:0] pe_seg_in,
    input wire [$clog2(SEG_HEIGHT)-1:0] pe_seg_line_no,

    output reg pe_set_busy,
    output wire [$clog2(SEG_CNT_TOT)-1:0] pe_seg_out,
    output reg pe_set_seg,
    // -------------------------

    input noc_out_ready,
    output wire [NOC_BIT_WIDTH-1:0] noc_out_data,
    output wire noc_out_valid,

    // For testing
    output reg done
);

reg [$clog2(SEG_CNT_TOT+1):0] next_seg;

// Extracts the appropriate line segment with halo pixels for the given segment index.
// Handles edge cases for halo pixels by zero-padding when out of bounds.
localparam SEG_W_NOPAD = IMG_WIDTH / SEG_CNT_X;
reg [SEG_WIDTH*PIX_WIDTH-1:0] segment_line;
reg [$clog2(SEG_CNT_X)-1:0] seg_idx_x;
always @ (*) begin
    seg_idx_x = SEG_CNT_X - 1 - (next_seg % SEG_CNT_X);
    segment_line[PIX_WIDTH*PADDING_X +: PIX_WIDTH*SEG_W_NOPAD] = img_line_in[SEG_W_NOPAD*PIX_WIDTH*seg_idx_x +: SEG_W_NOPAD*PIX_WIDTH]; // Main segment pixels
    if (seg_idx_x == 0)
        segment_line[PADDING_X*PIX_WIDTH-1:0] = 0; // Right halo
    else
        segment_line[PADDING_X*PIX_WIDTH-1:0] = img_line_in[(seg_idx_x - 1)*SEG_W_NOPAD*PIX_WIDTH +: PIX_WIDTH*PADDING_X]; // Right halo from previous segment
    if (seg_idx_x == SEG_CNT_X - 1)
        segment_line[SEG_WIDTH*PIX_WIDTH-1 -: PIX_WIDTH*PADDING_X] = 0; // Left halo
    else
        segment_line[SEG_WIDTH*PIX_WIDTH-1 -: PIX_WIDTH*PADDING_X] = img_line_in[SEG_W_NOPAD*PIX_WIDTH*(seg_idx_x + 1) +: PIX_WIDTH*PADDING_X]; // Left halo from next segment
end

reg [SEG_WIDTH*PIX_WIDTH-1:0] current_segment_line;
always @ (*) begin
    // Offset within segment + (Y component of segment * segment height)
    img_line_idx = pe_seg_line_no + ((pe_seg_in / SEG_CNT_X) * (IMG_HEIGHT/SEG_CNT_Y));

    if ((pe_seg_in / SEG_CNT_X == 0 && pe_seg_line_no == 0) ||
        (pe_seg_in / SEG_CNT_X == SEG_CNT_Y-1 && pe_seg_line_no == SEG_HEIGHT-1))
        current_segment_line = {SEG_WIDTH{{PIX_WIDTH{1'b0}}}};
    else
        current_segment_line = segment_line;
end

wire [CHUNK_WIDTH*PIX_WIDTH-1:0] tx_chunk_out;
wire [$clog2(SEG_WIDTH/CHUNK_WIDTH)-1:0] tx_chunk_idx;
wire tx_line_valid;
wire tx_line_complete;
wire tx_chunk_valid, tx_chunk_ready;

line_chunker #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(SEG_WIDTH),
    .CHUNK_WIDTH(CHUNK_WIDTH)
) LineChunker (
    .rst_n(rst_n),
    .clk(clk),
    .line_valid(tx_line_valid),
    .line_in(current_segment_line),
    .chunk_out_ready(tx_chunk_ready),
    .chunk_out(tx_chunk_out),
    .chunk_out_valid(tx_chunk_valid),
    .chunk_idx(tx_chunk_idx),
    .complete(tx_line_complete)
);

reg state;
localparam IDLE = 1'b0, SEND = 1'b1;
always @ (posedge clk) begin
    if (~rst_n) begin
        done <= 0;
        state <= IDLE;
        next_seg <= 0;
        pe_idx_x <= 0;
        pe_idx_y <= 1;
        pe_set_busy <= 0;
        pe_set_seg <=0;
    end else begin
        case (state)
        IDLE: if (~done) begin
            // Cycle through PEs to find an idle one, assign next segment, and move to SEND state. If no idle PE, stay in IDLE and check again next cycle.
            //$display("PE %d, %d: %b %d %d", pe_idx_x, pe_idx_y, pe_busy, pe_seg_in, pe_seg_line_no);

            // Make sure we leave idle PEs alone when we're waiting for the last segment to get done
            if (!pe_busy && !(next_seg == SEG_CNT_TOT && pe_seg_line_no == 0)) begin
                pe_set_busy <= 1;
                // Set segment number if this is a new segment
                pe_set_seg <= pe_seg_line_no == 0;
                state <= SEND;
            end else begin
                pe_set_busy <= 0;
                pe_set_seg <= 0;
                state <= IDLE;
                if (pe_idx_y == NOC_Y - 1) begin
                    pe_idx_x <= (pe_idx_x == NOC_X-1) ? 0 : pe_idx_x + 1;
                    pe_idx_y <= pe_idx_x == NOC_X-1; // Address (0, 0) is the dispatcher
                end else
                    pe_idx_y <= pe_idx_y + 1;
            end
        end else begin
            pe_set_busy <= 0;
            pe_set_seg <= 0;
        end

        // line_chunker is active and sending chunks for the assigned segment. Once complete, return to IDLE state.
        SEND: begin
            pe_set_busy <= 0;
            pe_set_seg <= 0;
            if (tx_line_complete) begin
                state <= IDLE;
                next_seg <= (pe_seg_line_no == 0) ? next_seg + 1 : next_seg;
                done <= pe_seg_in == SEG_CNT_TOT-1 && pe_seg_line_no == SEG_HEIGHT-1;
            end
        end
        endcase
    end
end

assign pe_seg_out = next_seg;

assign tx_line_valid = (state == SEND);
assign tx_chunk_ready = noc_out_ready;

// Pixel data, Chunk index, Source Y, Source X, Dest Y, Dest X
assign noc_out_data = (state == SEND) ?
    {tx_chunk_out, tx_chunk_idx, {$clog2(NOC_Y){1'b0}}, {$clog2(NOC_X){1'b0}}, pe_idx_y, pe_idx_x} :
    {NOC_BIT_WIDTH{1'b0}};
assign noc_out_valid = (state == SEND) ? tx_chunk_valid : 0;

endmodule
