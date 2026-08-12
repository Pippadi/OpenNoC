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

    output wire img_line_in_ready,
    output wire [$clog2(SEG_CNT_X*IMG_HEIGHT)-1:0] img_line_in_idx,
    input wire [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0] img_line_in,
    input wire img_line_in_valid,

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

    output reg done
    );

    reg [$clog2(SEG_CNT_TOT+1):0] next_seg;

    /*** Image Segmenting ***/

    // Extracts the appropriate line segment, and adds halo pixels for zero padding.
    reg [$clog2(SEG_CNT_TOT)-1:0] current_pe_seg; // Set before sending, see below
    wire [SEG_WIDTH*PIX_WIDTH-1:0] segment_line;
    reg segment_line_ready;
    wire segment_line_valid;

    seg_prepper #(
        .PIX_WIDTH(PIX_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .SEG_CNT_X(SEG_CNT_X),
        .SEG_CNT_Y(SEG_CNT_Y),
        .KERN_X(KERN_X),
        .KERN_Y(KERN_Y)
    ) SegPrepper (
        .rst_n(rst_n),
        .clk(clk),
        .pe_seg(current_pe_seg),
        .pe_seg_line_no(pe_seg_line_no),
        .img_line_in_ready(img_line_in_ready),
        .img_line_in_idx(img_line_in_idx),
        .img_line_in(img_line_in),
        .img_line_in_valid(img_line_in_valid),
        .segment_line_ready(segment_line_ready),
        .segment_line_valid(segment_line_valid),
        .segment_line(segment_line)
    );

    /*** Segment Dispatching ***/

    reg [SEG_WIDTH*PIX_WIDTH-1:0] current_segment_line; // Set when sending, see below

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
            segment_line_ready <= 0;
        end else begin
            case (state)
                IDLE: if (~done) begin
                    // Cycle through PEs to find an idle one, assign next segment, and move to SEND state. If no idle PE, stay in IDLE and check again next cycle.

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
                    segment_line_ready <= 1;
                    if (segment_line_valid) begin
                        segment_line_ready <= 0;
                        current_segment_line <= segment_line;
                        state <= SEND_LINE;
                    end
                end

                // line_chunker is active and sending chunks for the assigned segment. Once complete, return to IDLE state.
                SEND_LINE: begin
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

// initial $monitor("%d %d", state, segment_line_valid);

endmodule
