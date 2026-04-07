`timescale 1ns / 1ps

module orchestrator
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

    // Combinationally read
    output reg [$clog2(IMG_HEIGHT)-1:0] img_line_in_idx,
    input [IMG_WIDTH*PIX_WIDTH-1:0] img_line_in,

    // Valid signal asserted for a single cycle
    output wire [$clog2(SEG_CNT_TOT)-1:0] img_line_out_seg_idx,
    input [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0] img_line_out,
    output wire img_line_out_valid,

    input wire noc_in_valid,
    input wire [NOC_BIT_WIDTH-1:0] noc_in_data,
    output wire noc_in_ready,

    input noc_out_ready,
    output wire [NOC_BIT_WIDTH-1:0] noc_out_data,
    output wire noc_out_valid,

    // For testing
    output integer recvd_chunk_cnt,
    output wire done
);

// Map from PE index to segment index
reg [$clog2(SEG_CNT_TOT)-1:0] pe_seg_map [0:NOC_X-1][0:NOC_Y-1];
// Map from PE index to line number within segment
reg [$clog2(SEG_HEIGHT)-1:0] pe_seg_line_map [0:NOC_X-1][0:NOC_Y-1];
// Busy states of PEs
reg pe_busies [0:NOC_X-1][0:NOC_Y-1];

wire [$clog2(NOC_X)-1:0] disp_pe_x;
wire [$clog2(NOC_Y)-1:0] disp_pe_y;
wire disp_pe_set_busy;
wire disp_pe_set_seg;
wire [$clog2(SEG_CNT_TOT)-1:0] disp_pe_seg_out;

conv_dispatcher #(
    .PIX_WIDTH(PIX_WIDTH),
    .NOC_X(NOC_X),
    .NOC_Y(NOC_Y),
    .NOC_ADDR_X(NOC_ADDR_X),
    .NOC_ADDR_Y(NOC_ADDR_Y),
    .IMG_WIDTH(IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT),
    .CHUNK_WIDTH(CHUNK_WIDTH),
    .SEG_CNT_X(SEG_CNT_X),
    .SEG_CNT_Y(SEG_CNT_Y),
    .KERN_X(KERN_X),
    .KERN_Y(KERN_Y)
) Dispatcher (
    .rst_n(rst_n),
    .clk(clk),

    .img_line_idx(img_line_in_idx),
    .img_line_in(img_line_in),

    // --- PE info interface ---
    .pe_idx_x(disp_pe_x),
    .pe_idx_y(disp_pe_y),

    .pe_busy(pe_busies[disp_pe_x][disp_pe_y]),
    .pe_seg_in(pe_seg_map[disp_pe_x][disp_pe_y]),
    .pe_seg_line_no(pe_seg_line_map[disp_pe_x][disp_pe_y]),

    .pe_set_busy(disp_pe_set_busy),
    .pe_set_seg(disp_pe_set_seg),
    .pe_seg_out(disp_pe_seg_out),
    // -------------------------

    .noc_out_ready(noc_out_ready),
    .noc_out_data(noc_out_data),
    .noc_out_valid(noc_out_valid),

    // For testing
    .done(done)
);

wire [$clog2(NOC_X)-1:0] reas_pe_x;
wire [$clog2(NOC_Y)-1:0] reas_pe_y;
wire reas_line_out_valid;

reassembler #(
    .PIX_WIDTH(PIX_WIDTH),
    .NOC_X(NOC_X),
    .NOC_Y(NOC_Y),
    .NOC_ADDR_X(NOC_ADDR_X),
    .NOC_ADDR_Y(NOC_ADDR_Y),
    .IMG_WIDTH(IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT),
    .CHUNK_WIDTH(CHUNK_WIDTH),
    .SEG_CNT_X(SEG_CNT_X),
    .SEG_CNT_Y(SEG_CNT_Y),
    .KERN_X(KERN_X),
    .KERN_Y(KERN_Y)
) Reassembler (
    .rst_n(rst_n),
    .clk(clk),

    .noc_in_valid(noc_in_valid),
    .noc_in_data(noc_in_data),
    .noc_in_ready(noc_in_ready),

    .out_line_pe_x(reas_pe_x),
    .out_line_pe_y(reas_pe_y),
    .out_line(img_line_out),
    .out_line_valid(reas_line_out_valid)
);

assign img_line_out_seg_idx = pe_seg_map[reas_pe_x][reas_pe_y];
assign img_line_out_valid = reas_line_out_valid;

integer x, y;
always @ (posedge clk) begin
    if (~rst_n) begin
        for (x = 0; x < NOC_X; x = x + 1) begin
            for (y = 0; y < NOC_Y; y = y + 1) begin
                pe_seg_map[x][y] <= 0;
                pe_seg_line_map[x][y] <= 0;
                pe_busies[x][y] <= 0;
            end
        end
    end else begin
        if (disp_pe_set_busy && !(disp_pe_x == reas_pe_x && disp_pe_y == reas_pe_y && reas_line_out_valid))
            pe_busies[disp_pe_x][disp_pe_y] <= 1;
        else if (reas_line_out_valid) begin
            pe_busies[reas_pe_x][reas_pe_y] <= 0;
            pe_seg_line_map[reas_pe_x][reas_pe_y] <= (pe_seg_line_map[reas_pe_x][reas_pe_y] == SEG_HEIGHT-1) ? 0 : pe_seg_line_map[reas_pe_x][reas_pe_y] + 1;
        end

        if (disp_pe_set_seg)
            pe_seg_map[disp_pe_x][disp_pe_y] <= disp_pe_seg_out;
    end
end

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
