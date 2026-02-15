module conv_unit
#(
    parameter PIX_WIDTH = 8,
    parameter LINE_WIDTH = 16,
    parameter KERN_WIDTH = 3,
    parameter KERN_HEIGHT = 3
)
(
    input clk,
    input rst_n,
    input [KERN_WIDTH*KERN_HEIGHT*PIX_WIDTH-1:0] kern,
    input [LINE_WIDTH*PIX_WIDTH-1:0] line_in,
    input latch_line_in,
    output wire [2*PIX_WIDTH-1:0] pix_out,
    output wire line_req,
    output wire pix_out_valid
);

wire shift_en;
wire [KERN_WIDTH*KERN_HEIGHT*PIX_WIDTH-1:0] frame_to_conv;
wire top_linebuf_empty;
wire [PIX_WIDTH-1:0] linebuf_pix_outs [0:KERN_HEIGHT-1];

assign shift_en = ~top_linebuf_empty;
assign line_req = top_linebuf_empty;

linebuf_parallel_load #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(LINE_WIDTH),
    .KERN_WIDTH(KERN_WIDTH)
) TopLinebuf (
    .clk(clk),
    .rst_n(rst_n),
    .shift_en(shift_en),
    .latch_line_in(latch_line_in),
    .line_in(line_in),
    .pix_out(linebuf_pix_outs[0]),
    .section_out(frame_to_conv[0 +: KERN_WIDTH*PIX_WIDTH]),
    .buf_empty(top_linebuf_empty)
);

genvar i;
generate
    for (i = 1; i < KERN_HEIGHT; i = i + 1) begin
        linebuf #(
            .PIX_WIDTH(PIX_WIDTH),
            .LINE_WIDTH(LINE_WIDTH),
            .KERN_WIDTH(KERN_WIDTH)
        ) ALowerLinebuf (
            .clk(clk),
            .rst_n(rst_n),
            .shift_en(shift_en),
            .pix_in(linebuf_pix_outs[i-1]),
            .pix_out(linebuf_pix_outs[i]),
            .section_out(frame_to_conv[i*KERN_WIDTH*PIX_WIDTH +: KERN_WIDTH*PIX_WIDTH])
        );
    end
endgenerate

conv_math #(
    .PIX_WIDTH(PIX_WIDTH),
    .KERN_WIDTH(KERN_WIDTH),
    .KERN_HEIGHT(KERN_HEIGHT)
) conv_math_inst (
    .clk(clk),
    .rst_n(rst_n),
    .en(shift_en),
    .kern(kern),
    .pix_in(frame_to_conv),
    .pix_out(pix_out),
    .pix_out_valid(pix_out_valid)
);

endmodule
