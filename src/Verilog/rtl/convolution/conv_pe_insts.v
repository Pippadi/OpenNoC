`timescale 1ns / 1ps

module conv_pe_insts
#(
    parameter PIX_WIDTH = 8,
    parameter NOC_X = 4,
    parameter NOC_Y = 2,
    parameter NOC_ADDnoc_out_X = 1,
    parameter NOC_ADDnoc_out_Y = 1,
    parameter NOC_REASSEMBLEnoc_out_ADDnoc_out_X = 0,
    parameter NOC_REASSEMBLEnoc_out_ADDnoc_out_Y = 0,
    parameter LINE_WIDTH = 16,
    parameter CHUNK_WIDTH = 4,

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
    output wire done // For testing
);

genvar x, y;
generate
for (x = 0; x < NOC_X; x = x + 1) begin
    for (y = 0; y < NOC_Y; y = y + 1) begin
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
                .noc_in_ready(noc_out_readies[x+NOC_X*y]),
                .noc_out_ready(noc_out_valids[x+NOC_X*y]),
                .noc_out_data(noc_out_datas[(NOC_BIT_WIDTH*x)+(NOC_BIT_WIDTH*NOC_X*y)+:NOC_BIT_WIDTH]),
                .noc_out_valid(noc_in_readies[x+NOC_X*y]),
                .done(done)
            );
        end else begin
            convs #(
                .PIX_WIDTH(PIX_WIDTH),
                .LINE_WIDTH(LINE_WIDTH),
                .CHUNK_WIDTH(CHUNK_WIDTH),
                .NOC_X(NOC_X),
                .NOC_Y(NOC_Y),
                .NOC_ADDnoc_out_X(0),
                .NOC_ADDnoc_out_Y(1),
                .NOC_REASSEMBLEnoc_out_ADDnoc_out_X(0),
                .NOC_REASSEMBLEnoc_out_ADDnoc_out_Y(0)
            ) ConvPE (
                .clk(clk),
                .rst_n(rst_n),
                .noc_in_data(noc_in_datas[(NOC_BIT_WIDTH*x)+(NOC_BIT_WIDTH*NOC_X*y)+:NOC_BIT_WIDTH]),
    			.noc_in_ready(noc_out_readies[x+NOC_X*y]),
    			.noc_in_valid(noc_in_valids[x+NOC_X*y]),
    			.noc_out_data(noc_out_datas[(NOC_BIT_WIDTH*x)+(NOC_BIT_WIDTH*NOC_X*y)+:NOC_BIT_WIDTH]),
    			.noc_out_valid(noc_out_valids[x+NOC_X*y]),
    			.noc_out_ready(noc_in_readies[x+NOC_X*y])
            );
        end
	end
end
endgenerate

endmodule
