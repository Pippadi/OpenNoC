`timescale 1ns / 1ps

// NoC directions are from the perspective of the PE
module conv_pe_insts
#(
    parameter PIX_WIDTH = 8,
    parameter IMG_WIDTH = 512,
    parameter IMG_HEIGHT = 512,

    parameter NOC_X = 4,
    parameter NOC_Y = 2,

    parameter CHUNK_WIDTH = 6,
    parameter SEG_CNT_X = 2,
    parameter SEG_CNT_Y = 2,

    localparam SEG_WIDTH = IMG_WIDTH / SEG_CNT_X,
    localparam LINE_WIDTH = SEG_WIDTH + 2, // +2 for the halo pixels on each side. Assumes 3x3 kernel for now, parameterize later.

    localparam CHUNK_CNT_WIDTH = $clog2(LINE_WIDTH/CHUNK_WIDTH),
    localparam NOC_BIT_WIDTH = 2*($clog2(NOC_X)+$clog2(NOC_Y)) + CHUNK_CNT_WIDTH + CHUNK_WIDTH*PIX_WIDTH
)
(
    input  wire clk,
    input  wire rst_n,

    //PE interfaces
    output wire [(NOC_X*NOC_Y)-1:0]              noc_out_valids,
    output wire [(NOC_BIT_WIDTH*NOC_X*NOC_Y)-1:0] noc_out_datas,
    input  wire [(NOC_X*NOC_Y)-1:0]              noc_out_readies,

    input wire [(NOC_X*NOC_Y)-1:0]               noc_in_valids,
    input wire [(NOC_BIT_WIDTH*NOC_X*NOC_Y)-1:0]  noc_in_datas,
    output wire [(NOC_X*NOC_Y)-1:0]              noc_in_readies,

    // Dispatcher interfaces
    input wire [PIX_WIDTH*IMG_WIDTH-1:0] img_line_in,
    output wire [$clog2(IMG_HEIGHT)-1:0] img_line_idx,
    // For testing
    output wire [31:0] recvd_chunk_cnt,
    output wire done
);

genvar x, y;
generate
for (x = 0; x < NOC_X; x = x + 1) begin: xs
    for (y = 0; y < NOC_Y; y = y + 1) begin: ys
        if(x==0 & y==0) begin
			conv_dispatcher #(
                .PIX_WIDTH(PIX_WIDTH),
                .NOC_X(NOC_X),
                .NOC_Y(NOC_Y),
                .IMG_WIDTH(IMG_WIDTH),
                .IMG_HEIGHT(IMG_HEIGHT),
                .CHUNK_WIDTH(CHUNK_WIDTH),
                .SEG_CNT_X(SEG_CNT_X),
                .SEG_CNT_Y(SEG_CNT_Y)
            ) Dispatcher (
                .rst_n(rst_n),
                .clk(clk),
                .img_line_idx(img_line_idx),
                .img_line_in(img_line_in),

                .noc_in_valid(noc_in_valids[x+NOC_X*y]),
                .noc_in_data(noc_in_datas[(NOC_BIT_WIDTH*x)+(NOC_BIT_WIDTH*NOC_X*y)+:NOC_BIT_WIDTH]),
                .noc_in_ready(noc_in_readies[x+NOC_X*y]),

                .noc_out_valid(noc_out_valids[x+NOC_X*y]),
                .noc_out_data(noc_out_datas[(NOC_BIT_WIDTH*x)+(NOC_BIT_WIDTH*NOC_X*y)+:NOC_BIT_WIDTH]),
                .noc_out_ready(noc_out_readies[x+NOC_X*y]),

                .recvd_chunk_cnt(recvd_chunk_cnt),
                .done(done)
            );
        end else begin
            conv_pe #(
                .PIX_WIDTH(PIX_WIDTH),
                .LINE_WIDTH(LINE_WIDTH),
                .CHUNK_WIDTH(CHUNK_WIDTH),
                .NOC_X(NOC_X),
                .NOC_Y(NOC_Y),
                .NOC_ADDR_X(x),
                .NOC_ADDR_Y(y),
                .NOC_REASSEMBLER_ADDR_X(0),
                .NOC_REASSEMBLER_ADDR_Y(0)
            ) ConvPE (
                .clk(clk),
                .rst_n(rst_n),

                .noc_in_data(noc_in_datas[(NOC_BIT_WIDTH*x)+(NOC_BIT_WIDTH*NOC_X*y)+:NOC_BIT_WIDTH]),
                .noc_in_valid(noc_in_valids[x+NOC_X*y]),
    			.noc_in_ready(noc_in_readies[x+NOC_X*y]),

    			.noc_out_data(noc_out_datas[(NOC_BIT_WIDTH*x)+(NOC_BIT_WIDTH*NOC_X*y)+:NOC_BIT_WIDTH]),
    			.noc_out_valid(noc_out_valids[x+NOC_X*y]),
    			.noc_out_ready(noc_out_readies[x+NOC_X*y])
            );
        end
    end
end
endgenerate

endmodule
