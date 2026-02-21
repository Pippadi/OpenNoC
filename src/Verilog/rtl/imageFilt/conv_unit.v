`timescale 1ns / 1ps

// conv_unit performs convolution on pixel data from line buffers.
// `line_req` is asserted when the top line buffer is empty and ready to
// accept new data. `latch_line_in` should be asserted until `line_req` is
// deasserted. `pix_out` is the result of the convolution, and `pix_out_valid`
// is asserted for one cycle when `pix_out` is valid.
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
    output reg [PIX_WIDTH-1:0] pix_out,
    output wire line_req,
    output wire pix_out_valid
);

wire shift_en;
wire conv_en;
wire [KERN_WIDTH*KERN_HEIGHT*PIX_WIDTH-1:0] frame_to_conv;
wire conv_pix_out_valid;
wire [PIX_WIDTH-1:0] conv_pix_out;
wire top_linebuf_empty;
wire [PIX_WIDTH-1:0] linebuf_pix_outs [0:KERN_HEIGHT-1];

assign line_req = top_linebuf_empty;

reg [1:0] state;
localparam IDLE = 0, CONV = 1, SHIFT = 2;

assign pix_out_valid = (state == SHIFT); // Asserted for only one cycle

always @ (posedge clk) begin
    if (~rst_n) begin
        state <= IDLE;
    end else begin
        case (state)
            IDLE: state <= top_linebuf_empty ? IDLE : CONV;
            CONV: begin
                if (conv_pix_out_valid) begin
                    state <= SHIFT;
                    pix_out <= conv_pix_out;
                end
            end
            SHIFT: state <= IDLE;
        endcase
    end
end

assign shift_en = (state == SHIFT);
assign conv_en = (state == CONV);

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
) ConvolutionMath (
    .clk(clk),
    .rst_n(rst_n),
    .en(conv_en),
    .kern(kern),
    .img(frame_to_conv),
    .pix_out(conv_pix_out),
    .pix_out_valid(conv_pix_out_valid)
);

endmodule
