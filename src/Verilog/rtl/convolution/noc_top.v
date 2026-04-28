`timescale 1ns / 1ps

// `define BMP_HEADER_SIZE 13
`define BMP_HEADER_SIZE 1078
`define IMG_WIDTH 512
`define IMG_HEIGHT 512
`define PIX_WIDTH 8

// Most widths are in pixels, unless specified.

// Each PE processes a segment of the image. Each segment is fed line-by-line to the PEs.
// These lines are sent chunk-by-chunk over the NoC. Because NoC width is the ultimate parameter we want
// to optimize for, we parameterize the chunk width separately from the segment width.
// Segment width is calculated as (IMG_WIDTH / SEG_CNT_X) + (floor(KERN_X/2) * 4). Ensure CHUNK_WIDTH evenly
// divides segment width. Also ensure that the segment X and Y counts evenly divide the image width
// and height respectively.
`define CHUNK_WIDTH 14 // In pixels
`define SEG_CNT_X 4
`define SEG_CNT_Y 4
`define NOC_X 4 // NoC X dimension (number of columns of PEs)
`define NOC_Y 4 // NoC Y dimension (number of rows of PEs)

// The entire kernel must fit in one segment line (KERN_X*KERN_Y <= SEG_WIDTH).
`define KERN_X 7 // In pixels
`define KERN_Y 7
// Row-major
`define KERN {49{8'd7}} // Box blur
`define KERN_FRAC_BITS 6

module noc_top
(
    input wire rst_n,
    input wire clk,

    // AXI-Stream Slave Interface (From DMA Data Port)
    input  wire [31:0] s_axis_tdata,
    input  wire                 s_axis_tvalid,
    output wire                 s_axis_tready,
    input  wire                 s_axis_tlast,

    // To the PS for it to initiate DMA read
    output wire img_line_in_ready,
    output wire [$clog2(`IMG_HEIGHT*`SEG_CNT_X)-1:0] img_line_in_idx,

    output wire done
);

localparam PADDING_X = (`KERN_X / 2) * 2;
localparam PADDING_Y = (`KERN_Y / 2) * 2;

localparam SEG_WIDTH = `IMG_WIDTH / `SEG_CNT_X + 2*PADDING_X;
localparam SEG_HEIGHT = `IMG_HEIGHT / `SEG_CNT_Y + 2*PADDING_Y;
localparam SEG_CNT_TOT = `SEG_CNT_X * `SEG_CNT_Y;

localparam TYPE_WIDTH = 1;
localparam TYPE_IMG = 1'b1;
localparam TYPE_KERN = 1'b0;

localparam NOC_BIT_WIDTH = 2*($clog2(`NOC_X)+$clog2(`NOC_Y)) + $clog2(SEG_WIDTH/`CHUNK_WIDTH) + `CHUNK_WIDTH*`PIX_WIDTH + TYPE_WIDTH;

// Input to dispatcher
wire img_line_in_valid;
wire [(`IMG_WIDTH/`SEG_CNT_X)*`PIX_WIDTH-1:0] img_line_in;
wire [31:0] recvd_chunk_cnt; // For testing, counts the number of chunks received by the dispatcher

// Output from reassembler
wire [$clog2(`IMG_HEIGHT*`SEG_CNT_X)-1:0] img_line_out_idx;
wire [(`IMG_WIDTH/`SEG_CNT_X)*`PIX_WIDTH-1:0] img_line_out;
wire img_line_out_valid;

// Directions are from the perspective of the PE
wire [`NOC_X*`NOC_Y-1:0] noc_out_valids;
wire [NOC_BIT_WIDTH*`NOC_X*`NOC_Y-1:0] noc_out_datas;
wire [`NOC_X*`NOC_Y-1:0] noc_out_readies;
wire [`NOC_X*`NOC_Y-1:0] noc_in_valids;
wire [NOC_BIT_WIDTH*`NOC_X*`NOC_Y-1:0] noc_in_datas;
wire [`NOC_X*`NOC_Y-1:0] noc_in_readies;

(* DONT_TOUCH = "yes" *)
conv_pe_insts #(
    .PIX_WIDTH(`PIX_WIDTH),
    .NOC_X(`NOC_X),
    .NOC_Y(`NOC_Y),
    .IMG_WIDTH(`IMG_WIDTH),
    .IMG_HEIGHT(`IMG_HEIGHT),
    .CHUNK_WIDTH(`CHUNK_WIDTH),
    .SEG_CNT_X(`SEG_CNT_X),
    .SEG_CNT_Y(`SEG_CNT_Y),
    .TYPE_WIDTH(TYPE_WIDTH),
    .TYPE_IMG(TYPE_IMG),
    .TYPE_KERN(TYPE_KERN),
    .KERN_X(`KERN_X),
    .KERN_Y(`KERN_Y),
    .KERN(`KERN),
    .KERN_FRAC_BITS(`KERN_FRAC_BITS)
) PE_Insts (
    .rst_n(rst_n),
    .clk(clk),

    .noc_out_valids(noc_out_valids),
    .noc_out_datas(noc_out_datas),
    .noc_out_readies(noc_out_readies),

    .noc_in_valids(noc_in_valids),
    .noc_in_datas(noc_in_datas),
    .noc_in_readies(noc_in_readies),

    // Orchestrator interfaces
    .img_line_in_ready(img_line_in_ready),
    .img_line_in_idx(img_line_in_idx),
    .img_line_in(img_line_in),
    .img_line_in_valid(img_line_in_valid),

    .img_line_out(img_line_out),
    .img_line_out_idx(img_line_out_idx),
    .img_line_out_valid(img_line_out_valid),

    // For testing
    .done(done)
);

openNocTop #(
    .X(`NOC_X),
    .Y(`NOC_Y),
    .data_width(NOC_BIT_WIDTH-$clog2(`NOC_X)-$clog2(`NOC_Y)),
    .total_width(NOC_BIT_WIDTH),
    .if_width(NOC_BIT_WIDTH*`NOC_X*`NOC_Y),
    .pkt_no_field_size(0)
) NoC (
    .clk(clk),
    .rstn(rst_n),

    .r_data_pe(noc_out_datas),
    .r_valid_pe(noc_out_valids),
    .r_ready_pe(noc_out_readies),

    .w_ready_pe(noc_in_readies),
    .w_data_pe(noc_in_datas),
    .w_valid_pe(noc_in_valids)
);

endmodule
