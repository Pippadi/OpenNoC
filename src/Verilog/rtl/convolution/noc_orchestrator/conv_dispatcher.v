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

    localparam SEG_WIDTH = IMG_WIDTH / SEG_CNT_X,
    localparam SEG_HEIGHT = IMG_HEIGHT / SEG_CNT_Y,
    localparam SEG_CNT_TOT = SEG_CNT_X * SEG_CNT_Y,
    localparam LINE_WIDTH = SEG_WIDTH + 2, // +2 for the halo pixels on each side. Assumes 3x3 kernel for now, parameterize later.

    localparam NOC_BIT_WIDTH = 2*($clog2(NOC_X)+$clog2(NOC_Y)) + $clog2(LINE_WIDTH/CHUNK_WIDTH) + CHUNK_WIDTH*PIX_WIDTH
)
(
    input rst_n,
    input clk,

    output wire [$clog2(IMG_HEIGHT)-1:0] img_line_idx,
    input [IMG_WIDTH*PIX_WIDTH-1:0] img_line_in,

    input wire noc_in_valid,
    input wire [NOC_BIT_WIDTH-1:0] noc_in_data,
    output wire noc_in_ready,

    input noc_out_ready,
    output wire [NOC_BIT_WIDTH-1:0] noc_out_data,
    output wire noc_out_valid,

    // For testing
    output integer recvd_chunk_cnt,
    output reg done
);

integer i, j;

// Map from PE index to segment index
// Most significant bit for idle, next bits for segment index, remaining bits for line index
// Is there a better way to do this?
localparam PE_MAP_WIDTH = 1 + $clog2(SEG_CNT_TOT) + $clog2(SEG_HEIGHT);
reg [PE_MAP_WIDTH-1:0] pe_segment_map [0:NOC_X-1][0:NOC_Y-1];

// segment_line extracts the appropriate line segment with halo pixels for the given segment index.
// It handles edge cases for halo pixels by zero-padding when out of bounds.
function automatic [LINE_WIDTH*PIX_WIDTH-1:0] segment_line(input [IMG_WIDTH*PIX_WIDTH-1:0] img_line, input reg [$clog2(SEG_CNT_TOT)-1:0] seg_idx); begin
    segment_line[PIX_WIDTH +: PIX_WIDTH*SEG_WIDTH] = img_line[SEG_WIDTH*PIX_WIDTH*(seg_idx % SEG_CNT_X) +: SEG_WIDTH*PIX_WIDTH]; // Main segment pixels
    if (seg_idx % SEG_CNT_TOT == 0)
        segment_line[PIX_WIDTH-1:0] = 0; // Right halo
    else
        segment_line[PIX_WIDTH-1:0] = img_line[(seg_idx % SEG_CNT_X - 1)*SEG_WIDTH*PIX_WIDTH +: PIX_WIDTH]; // Right halo from previous segment
    if (seg_idx % SEG_CNT_X == SEG_CNT_X - 1)
        segment_line[LINE_WIDTH*PIX_WIDTH-1 -: PIX_WIDTH] = 0; // Left halo
    else
        segment_line[LINE_WIDTH*PIX_WIDTH-1 -: PIX_WIDTH] = img_line[SEG_WIDTH*PIX_WIDTH*(seg_idx % SEG_CNT_X + 1) +: PIX_WIDTH]; // Left halo from next segment
end
endfunction

reg [$clog2(SEG_CNT_TOT)-1:0] next_seg;
reg [$clog2(NOC_X)-1:0] pe_idx_x;
reg [$clog2(NOC_Y)-1:0] pe_idx_y;

wire [CHUNK_WIDTH*PIX_WIDTH-1:0] tx_chunk_out;
wire [$clog2(LINE_WIDTH/CHUNK_WIDTH)-1:0] tx_chunk_idx;
wire tx_line_valid;
wire tx_line_complete;
wire tx_chunk_valid, tx_chunk_ready;

assign img_line_idx =
    pe_segment_map[pe_idx_x][pe_idx_y][$clog2(SEG_HEIGHT)-1:0] +
    (pe_segment_map[pe_idx_x][pe_idx_y][$clog2(SEG_HEIGHT)+:$clog2(SEG_CNT_TOT)] / SEG_CNT_X) * SEG_HEIGHT;
wire [LINE_WIDTH*PIX_WIDTH-1:0] current_segment_line = segment_line(img_line_in, next_seg);

line_chunker #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(LINE_WIDTH),
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
        for (i = 0; i < NOC_X; i = i + 1)
            for (j = 0; j < NOC_Y; j = j + 1)
                pe_segment_map[i][j] <= {PE_MAP_WIDTH{1'b0}};

    end else begin
        case (state)
        IDLE: if (~done) begin
            // Cycle through PEs to find an idle one, assign next segment, and move to SEND state. If no idle PE, stay in IDLE and check again next cycle.
            $display("PE %d, %d: %b", pe_idx_x, pe_idx_y, pe_segment_map[pe_idx_x][pe_idx_y]);
            if (pe_segment_map[pe_idx_x][pe_idx_y][PE_MAP_WIDTH-1] == 0) begin
                // Mark PE as busy, assign segment index, and preserve line index (incremented when line received by PE)
                pe_segment_map[pe_idx_x][pe_idx_y] <= {1'b1, next_seg, pe_segment_map[pe_idx_x][pe_idx_y][$clog2(SEG_HEIGHT)-1:0]};
                state <= SEND;
            end else begin
                state <= IDLE;
                if (pe_idx_y == NOC_Y - 1) begin
                    pe_idx_x <= (pe_idx_x == NOC_X-1) ? 0 : pe_idx_x + 1;
                    pe_idx_y <= pe_idx_x == NOC_X-1; // Address (0, 0) is the dispatcher
                end else
                    pe_idx_y <= pe_idx_y + 1;
            end
        end

        // line_chunker is active and sending chunks for the assigned segment. Once complete, return to IDLE state.
        SEND: begin
             if (tx_line_complete) begin
                 state <= IDLE;
                 next_seg <= next_seg + 1;
                 done <= next_seg == SEG_CNT_TOT-1;
             end
        end
        endcase
    end
end

assign tx_line_valid = (state == SEND);

// Pixel data, Chunk index, Source X, Source Y, Dest X, Dest Y,
assign noc_out_data = (state == SEND) ? {tx_chunk_out, tx_chunk_idx, {$clog2(NOC_X){1'b0}}, {$clog2(NOC_Y){1'b0}}, pe_idx_x, pe_idx_y} : {NOC_BIT_WIDTH{1'b0}};
assign noc_out_valid = (state == SEND) ? tx_chunk_valid : 0;
assign tx_chunk_ready = noc_out_ready;


/* Remove when we have a reassembler (drops processed chunks for now) */
// TODO: Increment line number for PE
assign noc_in_ready = 1;
always @ (posedge clk) begin
    if (~rst_n) begin
        recvd_chunk_cnt <= 0;
    end else begin
        if (noc_in_valid)
            recvd_chunk_cnt <= recvd_chunk_cnt + 1;
    end
end
/********************************************/

endmodule
