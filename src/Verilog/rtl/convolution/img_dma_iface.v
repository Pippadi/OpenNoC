`timescale 1ns / 1ps

module img_dma_iface
#(
    parameter PIX_WIDTH = 8,
    parameter IMG_WIDTH = 512,
    parameter SEG_CNT_X = 4,
    parameter DMA_DATA_WIDTH = 32
)
(
    input wire rst_n,
    input wire clk,

    input wire                                          img_line_in_ready,
    output reg                                          img_line_in_valid,
    input wire [$clog2(IMG_WIDTH*SEG_CNT_X)-1:0]        img_line_in_idx,
    output reg [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0]    img_line_in,

    output wire img_line_out_ready,
    input wire [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0] img_line_out,
    input wire img_line_out_valid,

    output reg dma_read_ready,
    output wire [$clog2(IMG_WIDTH*SEG_CNT_X)-1:0] dma_read_line_idx,

    input  wire [DMA_DATA_WIDTH-1:0] mm2s_axis_tdata,
    input  wire mm2s_axis_tvalid,
    output wire mm2s_axis_tready,
    input  wire mm2s_axis_tlast,

    output wire [DMA_DATA_WIDTH-1:0] s2mm_axis_tdata,
    output wire s2mm_axis_tvalid,
    input  wire s2mm_axis_tready,
    output wire s2mm_axis_tlast
);


// DDR to dispatcher
reg reading_line;

assign mm2s_axis_tready = img_line_in_ready;
assign dma_read_line_idx = img_line_in_idx;

always @ (posedge clk) begin
    if (~rst_n) begin
        img_line_in_valid <= 0;
        img_line_in <= {(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH{1'b0}};
        reading_line <= 0;
        dma_read_ready <= 0;
    end else begin
        if (img_line_in_ready & ~reading_line) begin
            reading_line <= 1;
            dma_read_ready <= 1;
        end

        if (reading_line) begin
            if (mm2s_axis_tvalid && mm2s_axis_tready) begin
                // Shift in the incoming data into img_line_in
                img_line_in <= {img_line_in[(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH - DMA_DATA_WIDTH - 1:0], mm2s_axis_tdata};
                // If this is the last beat of the segment, assert valid
                img_line_in_valid <= mm2s_axis_tlast;
                dma_read_ready <= ~mm2s_axis_tlast;
            end else if (img_line_in_valid && img_line_in_ready) begin
                // Once the dispatcher has accepted the line, we can deassert valid
                img_line_in_valid <= 0;
                reading_line <= 0;
                dma_read_ready <= 0;
            end
        end
    end
end

// Reassembler to DDR

wire [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0] img_line_out_rev;
word_rev #(.W_CNT(IMG_WIDTH/SEG_CNT_X), .W_WIDTH(PIX_WIDTH)) DmaTDataRev (
    .data_in(img_line_out),
    .data_out(img_line_out_rev)
);

reg [$clog2((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH/DMA_DATA_WIDTH)-1:0] shift_cnt;
assign s2mm_axis_tvalid = (shift_cnt < ((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH)/DMA_DATA_WIDTH) && img_line_out_valid;
assign s2mm_axis_tlast = (shift_cnt == ((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH)/DMA_DATA_WIDTH - 1) && img_line_out_valid;
assign s2mm_axis_tdata = img_line_out_rev[shift_cnt*DMA_DATA_WIDTH +: DMA_DATA_WIDTH];
assign img_line_out_ready = s2mm_axis_tlast;

always @ (posedge clk) begin
    if (~rst_n | ~img_line_out_valid) begin
        shift_cnt <= 0;
    end else begin
        if (shift_cnt < (IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH/DMA_DATA_WIDTH && s2mm_axis_tready) begin
            shift_cnt <= shift_cnt + 1;
        end
    end
end

endmodule
