`timescale 1ns / 1ps

module conv_pe
#(
    parameter PIX_WIDTH = 8,
    parameter NOC_X = 4,
    parameter NOC_Y = 2,
    parameter NOC_ADDR_X = 2'd1,
    parameter NOC_ADDR_Y = 1'd1,
    parameter NOC_REASSEMBLER_ADDR_X = 0,
    parameter NOC_REASSEMBLER_ADDR_Y = 0,
    parameter LINE_WIDTH = 16,
    parameter CHUNK_WIDTH = 4,

    parameter TYPE_WIDTH = 1,
    parameter TYPE_IMG = 1'b1,
    parameter TYPE_KERN = 1'b0,

    parameter KERN_X = 3,
    parameter KERN_Y = 3,

    localparam CHUNK_CNT_WIDTH = $clog2(LINE_WIDTH/CHUNK_WIDTH),
    localparam NOC_BIT_WIDTH = 2*($clog2(NOC_X)+$clog2(NOC_Y)) + CHUNK_CNT_WIDTH + CHUNK_WIDTH*PIX_WIDTH + TYPE_WIDTH
)
(
    input wire clk,
    input wire rst_n,

    input wire noc_in_valid,
    input wire [NOC_BIT_WIDTH-1:0] noc_in_data,
    output wire noc_in_ready,

    input wire noc_out_ready,
    output wire [NOC_BIT_WIDTH-1:0] noc_out_data,
    output wire noc_out_valid
);

reg conv_latch_line;
wire conv_pix_valid;
wire conv_line_req;
wire [PIX_WIDTH-1:0] conv_pix;

wire [LINE_WIDTH*PIX_WIDTH-1:0] line;
reg chunkbuf_line_clear;
wire chunkbuf_line_valid;
reg chunkbuf_chunk_avail;

wire [CHUNK_CNT_WIDTH-1:0] chunk_idx_in = noc_in_data[2*($clog2(NOC_X)+$clog2(NOC_Y)) + TYPE_WIDTH +: CHUNK_CNT_WIDTH];
wire [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_in = noc_in_data[NOC_BIT_WIDTH-1 -: CHUNK_WIDTH*PIX_WIDTH];
wire [TYPE_WIDTH-1:0] pkt_type = noc_in_data[2*($clog2(NOC_X)+$clog2(NOC_Y))];

// To hold the kernel
localparam KERN_CHUNK_CNT = $rtoi($ceil($itor(KERN_X*KERN_Y) / $itor(CHUNK_WIDTH)));
localparam KERN_BUF_WIDTH = KERN_CHUNK_CNT * CHUNK_WIDTH;
wire [KERN_BUF_WIDTH*PIX_WIDTH-1:0] kern_buf;
line_chunk_buffer #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(KERN_BUF_WIDTH),
    .CHUNK_WIDTH(CHUNK_WIDTH)
) KernChunkBuffer (
    .rst_n(rst_n),
    .clk(clk),
    .chunk_avail(noc_in_valid && pkt_type == TYPE_KERN && chunk_idx_in < KERN_CHUNK_CNT),
    .chunk_idx(chunk_idx_in),
    .chunk(chunk_in),
    .line_clear(1'b0),
    .line(kern_buf),
    .line_valid()
);

// For image lines
line_chunk_buffer #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(LINE_WIDTH),
    .CHUNK_WIDTH(CHUNK_WIDTH)
) LineChunkBuffer (
    .rst_n(rst_n),
    .clk(clk),
    .chunk_avail(chunkbuf_chunk_avail),
    .chunk_idx(chunk_idx_in),
    .chunk(chunk_in),
    .line_clear(chunkbuf_line_clear),
    .line(line),
    .line_valid(chunkbuf_line_valid)
);

conv_unit #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(LINE_WIDTH),
    .KERN_FRAC_BITS(6),
    .KERN_WIDTH(3),
    .KERN_HEIGHT(3)
) ConvUnit (
    .rst_n(rst_n),
    .clk(clk),
    .kern(kern_buf[KERN_X*KERN_Y*PIX_WIDTH-1:0]),
    .line_in(line),
    .latch_line_in(conv_latch_line),
    .line_req(conv_line_req),
    .pix_out(conv_pix),
    .pix_out_valid(conv_pix_valid)
);

// State machine to load the conv unit when it requests a line and the chunk buffer is valid,
// then clear the chunk buffer afterwards
localparam S_IDLE  = 2'd0, S_LATCH = 2'd1;

reg state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        conv_latch_line <= 1'b0;
        chunkbuf_line_clear <= 1'b0;
        chunkbuf_chunk_avail <= 1'b0;
    end else begin
        case (state)
            S_IDLE: begin
                // Wait for conv unit request and a valid line from the chunk buffer
                chunkbuf_line_clear <= 1'b0;
                chunkbuf_chunk_avail <= noc_in_valid && pkt_type == TYPE_IMG;
                if (conv_line_req && chunkbuf_line_valid) begin
                    // Pulse latch for one cycle to load the line into the convolution unit
                    conv_latch_line <= 1'b1;
                    state <= S_LATCH;
                end else begin
                    conv_latch_line <= 1'b0;
                    state <= S_IDLE;
                end
            end

            S_LATCH: begin
                chunkbuf_line_clear <= 1'b1;  // Clear the chunk buffer for the next line
                chunkbuf_chunk_avail <= 1'b0; // Make sure clearing the buffer happens first
                conv_latch_line <= 1'b0;
                state <= S_IDLE;
            end
        endcase
    end
end

/*** Output chunking ***/

reg [CHUNK_CNT_WIDTH-1:0] output_chunk_ctr;
wire [CHUNK_WIDTH*PIX_WIDTH-1:0] output_chunk;

output_chunker #(
    .PIX_WIDTH(PIX_WIDTH),
    .CHUNK_WIDTH(CHUNK_WIDTH)
) OutputChunker (
    .rst_n(rst_n),
    .clk(clk),
    .pix_in_valid(conv_pix_valid),
    .pix_in(conv_pix),
    .chunk_out_ready(noc_out_ready),
    .chunk_out(output_chunk),
    .chunk_out_valid(noc_out_valid)
);

// Pixel data, Chunk index, Packet type, Source Y, Source X, Dest Y, Dest X
assign noc_out_data = {output_chunk, output_chunk_ctr, TYPE_IMG, NOC_ADDR_Y[$clog2(NOC_Y)-1:0], NOC_ADDR_X[$clog2(NOC_X)-1:0], NOC_REASSEMBLER_ADDR_Y[$clog2(NOC_Y)-1:0], NOC_REASSEMBLER_ADDR_X[$clog2(NOC_X)-1:0]};
assign noc_in_ready = state == S_IDLE;

always @ (posedge clk) begin
    if (~rst_n)
        output_chunk_ctr <= LINE_WIDTH/CHUNK_WIDTH-1;
    else begin
        if (noc_out_valid & noc_out_ready) // Decrement only when chunk has been accepted by the NoC
            output_chunk_ctr <= (output_chunk_ctr == 0) ? LINE_WIDTH/CHUNK_WIDTH-1 : output_chunk_ctr-1;
    end
end

endmodule
