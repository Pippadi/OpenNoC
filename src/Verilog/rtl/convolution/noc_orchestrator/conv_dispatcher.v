`timescale 1ns / 1ps

module conv_dispatcher
#(
    parameter PIX_WIDTH = 8,

    parameter NOC_X = 2,
    parameter NOC_Y = 2,

    parameter NOC_ADDR_X = 0,
    parameter NOC_ADDR_Y = 0,

    parameter IMG_WIDTH = 512,
    parameter IMG_HEIGHT = 512,
    parameter CHUNK_WIDTH = 6,
    parameter SEG_CNT_X = 2,
    parameter SEG_CNT_Y = 2,

    parameter TYPE_WIDTH = 1,
    parameter TYPE_IMG = 1'b1,
    parameter TYPE_KERN = 1'b0,

    parameter KERN_X = 3,
    parameter KERN_Y = 3,
    parameter KERN = {8'd7, 8'd7, 8'd7, 8'd7, 8'd7, 8'd7, 8'd7, 8'd7, 8'd7},

    localparam PADDING_X = (KERN_X / 2) * 2,
    localparam PADDING_Y = (KERN_Y / 2) * 2,

    localparam SEG_WIDTH = IMG_WIDTH / SEG_CNT_X + 2*PADDING_X,
    localparam SEG_HEIGHT = IMG_HEIGHT / SEG_CNT_Y + 2*PADDING_Y,
    localparam SEG_CNT_TOT = SEG_CNT_X * SEG_CNT_Y,

    localparam NOC_BIT_WIDTH = 2*($clog2(NOC_X)+$clog2(NOC_Y)) + $clog2(SEG_WIDTH/CHUNK_WIDTH) + CHUNK_WIDTH*PIX_WIDTH + TYPE_WIDTH
)
(
    input rst_n,
    input clk,

    output wire [$clog2(IMG_HEIGHT)-1:0] img_line_idx,
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

/*** Image Segmenting ***/

// Offset within segment + (Y component of segment * segment height)
assign img_line_idx = pe_seg_line_no + ((pe_seg_in / SEG_CNT_X) * (IMG_HEIGHT/SEG_CNT_Y));

// Extracts the appropriate line segment, and adds halo pixels for zero padding.
localparam SEG_W_NOPAD = IMG_WIDTH / SEG_CNT_X;
reg [$clog2(SEG_CNT_TOT)-1:0] current_pe_seg; // Set before sending, see below
reg [SEG_WIDTH*PIX_WIDTH-1:0] segment_line;
reg [$clog2(SEG_CNT_X)-1:0] seg_idx_x;
always @ (*) begin
    seg_idx_x = current_pe_seg % SEG_CNT_X;
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

// If the line number within the segment is 0, and the segment is at the top of
// the image, or the segment line number is the bottommost, and the segment is
// along the bottom of the image, the line must be zero (zero padding).
wire line_is_top_bottom =
    (pe_seg_in / SEG_CNT_X == 0 && pe_seg_line_no == 0) ||
    (pe_seg_in / SEG_CNT_X == SEG_CNT_Y-1 && pe_seg_line_no == SEG_HEIGHT-1);
reg [SEG_WIDTH*PIX_WIDTH-1:0] current_segment_line; // Set when sending, see below

/*** Segment Dispatching ***/

wire [CHUNK_WIDTH*PIX_WIDTH-1:0] tx_line_chunk_out;
wire [$clog2(SEG_WIDTH/CHUNK_WIDTH)-1:0] tx_line_chunk_idx;
wire tx_line_valid;
wire tx_line_complete;
wire tx_line_chunk_valid, tx_line_chunk_ready;

line_chunker #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(SEG_WIDTH),
    .CHUNK_WIDTH(CHUNK_WIDTH)
) LineChunker (
    .rst_n(rst_n),
    .clk(clk),
    .line_valid(tx_line_valid),
    .line_in(current_segment_line),
    .chunk_out_ready(tx_line_chunk_ready),
    .chunk_out(tx_line_chunk_out),
    .chunk_out_valid(tx_line_chunk_valid),
    .chunk_idx(tx_line_chunk_idx),
    .complete(tx_line_complete)
);

reg [1:0] state;
localparam IDLE = 2'b00, SEND_KERNEL = 2'b01, CALC_SEGMENT = 2'b10, SEND_LINE = 2'b11;
always @ (posedge clk) begin
    if (~rst_n) begin
        done <= 0;
        state <= IDLE;
        next_seg <= 0;
        pe_idx_x <= 0;
        pe_idx_y <= 1;
        pe_set_busy <= 0;
        pe_set_seg <= 0;
        current_pe_seg <= 0;
        current_segment_line <= {SEG_WIDTH{{PIX_WIDTH{1'b0}}}};
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
                // We need segment number for segment calculation, but the map in the orchestrator
                // will be updated one cycle too late, so we're storing it here
                current_pe_seg <= (pe_seg_line_no == 0) ? next_seg : pe_seg_in;
                state <= (pe_seg_line_no == 0) ? SEND_KERNEL : CALC_SEGMENT;
                current_segment_line <= {{((SEG_WIDTH-KERN_X*KERN_Y)*PIX_WIDTH){1'b0}}, KERN};
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

        SEND_KERNEL: begin
            pe_set_busy <= 0;
            pe_set_seg <= 0;
            state <= tx_line_complete ? CALC_SEGMENT : SEND_KERNEL;
        end

        CALC_SEGMENT: begin
            pe_set_busy <= 0;
            pe_set_seg <= 0;
            current_segment_line <= line_is_top_bottom ? {SEG_WIDTH{{PIX_WIDTH{1'b0}}}} : segment_line;
            state <= SEND_LINE;
        end

        // line_chunker is active and sending chunks for the assigned segment. Once complete, return to IDLE state.
        SEND_LINE: begin
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

assign tx_line_valid = (state == SEND_LINE || state == SEND_KERNEL);
assign tx_line_chunk_ready = noc_out_ready;

// Pixel data, Chunk index, Source Y, Source X, Dest Y, Dest X
assign noc_out_data = (state == SEND_KERNEL || state == SEND_LINE) ?
    {tx_line_chunk_out, tx_line_chunk_idx, (state == SEND_KERNEL) ? TYPE_KERN : TYPE_IMG, {$clog2(NOC_Y){1'b0}}, {$clog2(NOC_X){1'b0}}, pe_idx_y, pe_idx_x} :
    {NOC_BIT_WIDTH{1'b0}};
assign noc_out_valid = (state == SEND_LINE || state == SEND_KERNEL) ? tx_line_chunk_valid : 1'b0;

initial $monitor("%h, %d", noc_out_data, state);

endmodule
