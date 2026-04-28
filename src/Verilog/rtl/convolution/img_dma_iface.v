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

    // Dispatcher Interface
    input wire                                          img_line_in_ready,
    output reg                                          img_line_in_valid,
    output reg [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0]    img_line_in,

    // AXI-Stream Slave Interface (From DMA Data Port)
    input  wire [DMA_DATA_WIDTH-1:0] s_axis_tdata,
    input  wire s_axis_tvalid,
    output wire s_axis_tready,
    input  wire s_axis_tlast
);

always @ (posedge clk) begin
    if (~rst_n) begin
        img_line_in_valid <= 0;
        img_line_in <= {(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH{1'b0}};
    end else begin
        if (s_axis_tvalid && s_axis_tready) begin
            // Shift in the incoming data into img_line_in
            img_line_in <= {img_line_in[(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH - DMA_DATA_WIDTH - 1:0], s_axis_tdata};
            // If this is the last beat of the segment, assert valid
            img_line_in_valid <= s_axis_tlast;
        end else if (img_line_in_valid && img_line_in_ready) begin
            // Once the dispatcher has accepted the line, we can deassert valid
            img_line_in_valid <= 0;
        end
    end
end

endmodule
