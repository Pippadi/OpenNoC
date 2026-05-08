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

    // Reassembler Interface
    output wire img_line_out_ready,
    input wire [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0] img_line_out,
    input wire img_line_out_valid,

    // AXI-Stream Slave Interface (From DMA Data Port)
    input  wire [DMA_DATA_WIDTH-1:0] mm2s_axis_tdata,
    input  wire mm2s_axis_tvalid,
    output wire mm2s_axis_tready,
    input  wire mm2s_axis_tlast,

    // AXI-Stream Slave Interface (To DMA Control Port)
    output wire [DMA_DATA_WIDTH-1:0] s2mm_axis_tdata,
    output wire s2mm_axis_tvalid,
    input  wire s2mm_axis_tready,
    output wire s2mm_axis_tlast
);

// Orchestrator interface passthroughs
assign mm2s_axis_tready = img_line_in_ready;

always @ (posedge clk) begin
    if (~rst_n) begin
        img_line_in_valid <= 0;
        img_line_in <= {(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH{1'b0}};
    end else begin
        if (mm2s_axis_tvalid && mm2s_axis_tready) begin
            // Shift in the incoming data into img_line_in
            img_line_in <= {img_line_in[(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH - DMA_DATA_WIDTH - 1:0], mm2s_axis_tdata};
            // If this is the last beat of the segment, assert valid
            img_line_in_valid <= mm2s_axis_tlast;
        end else if (img_line_in_valid && img_line_in_ready) begin
            // Once the dispatcher has accepted the line, we can deassert valid
            img_line_in_valid <= 0;
        end
    end
end

// Reassembler interface passthroughs

reg [$clog2((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH/DMA_DATA_WIDTH)-1:0] shift_cnt;
assign s2mm_axis_tdata = img_line_out[shift_cnt*DMA_DATA_WIDTH +: DMA_DATA_WIDTH];
assign s2mm_axis_tvalid = (shift_cnt < ((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH)/DMA_DATA_WIDTH) && img_line_out_valid;
assign s2mm_axis_tlast = (shift_cnt == ((IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH)/DMA_DATA_WIDTH - 1) && img_line_out_valid;
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
