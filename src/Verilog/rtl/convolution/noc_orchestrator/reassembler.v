`timescale 1ns / 1ps

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

    localparam NOC_BIT_WIDTH = 2*($clog2(NOC_X)+$clog2(NOC_Y)) + $clog2(SEG_WIDTH/CHUNK_WIDTH) + CHUNK_WIDTH*PIX_WIDTH
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

    output reg [$clog2(NOC_X)-1:0] out_line_pe_x,
    output reg [$clog2(NOC_Y)-1:0] out_line_pe_y,
    // Segment line to be output
    output reg [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0] out_line,
    // Assert for one cycle, no acknowledgement needed
    output reg out_line_valid
);

wire [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_in = noc_in_data[NOC_BIT_WIDTH-1 -: CHUNK_WIDTH*PIX_WIDTH];
wire [$clog2(SEG_WIDTH/CHUNK_WIDTH)-1:0] chunk_in_idx = noc_in_data[2*($clog2(NOC_X)+$clog2(NOC_Y)) +: $clog2(SEG_WIDTH/CHUNK_WIDTH)];
wire [$clog2(NOC_X)-1:0] pe_x_idx = noc_in_data[2*($clog2(NOC_X)+$clog2(NOC_Y))-1 -: $clog2(NOC_X)];
wire [$clog2(NOC_Y)-1:0] pe_y_idx = noc_in_data[($clog2(NOC_X)+$clog2(NOC_Y)) +: $clog2(NOC_Y)];

reg buf_line_clears [0:NOC_X-1][0:NOC_Y-1];
reg [SEG_WIDTH*PIX_WIDTH-1:0] buf_line_outs [0:NOC_X-1][0:NOC_Y-1];
wire [NOC_X*NOC_Y-1:0] buf_line_valids;
genvar x, y;
generate
    for (x = 0; x < NOC_X; x = x + 1) begin : gen_pe_x
        for (y = 0; y < NOC_Y; y = y + 1) begin : gen_pe_y
            if (!(x == 0 && y == 0)) begin: gen_pe
                line_chunk_buffer #(
                    .PIX_WIDTH(PIX_WIDTH),
                    .LINE_WIDTH(SEG_WIDTH),
                    .CHUNK_WIDTH(CHUNK_WIDTH)
                ) ALineChunkBuffer (
                    .rst_n(rst_n),
                    .clk(clk),
                    .chunk_avail(noc_in_valid && pe_x_idx == x && pe_y_idx == y),
                    .chunk_idx(chunk_in_idx),
                    .chunk(chunk_in),
                    .line_clear(buf_line_clears[x][y]),
                    .line(buf_line_outs[x][y]),
                    .line_valid(buf_line_valids[x*NOC_Y+y])
                );
            end
        end
    end
endgenerate

wire [$clog2(NOC_X*NOC_Y)-1:0] out_line_pe_idx;
priority_encoder #(.N(NOC_X*NOC_Y)) LineValidEncoder (
    .in(buf_line_valids),
    .out(out_line_pe_idx)
);

integer i, j;
reg [1:0] state;
localparam IDLE = 2'b00, OUTPUT = 2'b01, CLEAR = 2'b10;
always @ (posedge clk) begin
    if (~rst_n) begin
        out_line_valid <= 0;
        out_line_pe_x <= 0;
        out_line_pe_y <= 0;
        for (i = 0; i < NOC_X; i = i + 1)
            for (j = 0; j < NOC_Y; j = j + 1)
                buf_line_clears[i][j] <= 0;
        state <= IDLE;
    end else begin
        case (state)
            IDLE: begin
                if (|buf_line_valids) begin
                    out_line_valid <= 1;
                    out_line_pe_x <= out_line_pe_idx / NOC_Y;
                    out_line_pe_y <= out_line_pe_idx % NOC_Y;
                    state <= OUTPUT;
                end
            end

            OUTPUT: begin
                out_line_valid <= 0;
                buf_line_clears[out_line_pe_x][out_line_pe_y] <= 1;
                state <= CLEAR;
            end

            CLEAR: begin
                state <= IDLE;
                buf_line_clears[out_line_pe_x][out_line_pe_y] <= 0;
            end
        endcase
    end
end

// This could fail if chunks from the same PE but for different lines arrive at back-to-back cycles,
// but that's highly unlikely.
assign noc_in_ready = ~(state == OUTPUT && out_line_pe_x == pe_x_idx && out_line_pe_y == pe_y_idx);

assign out_line = buf_line_outs[out_line_pe_x][out_line_pe_y][(SEG_WIDTH-PADDING_X)*PIX_WIDTH : PADDING_X*PIX_WIDTH];

endmodule
