`timescale 1ns / 1ps

// Same as linebuf, but loads a full line in parallel instead of shifting in
// pixel-by-pixel. Built with the assumption that the module feeding it does
// packet reassembly to provide full lines at a time.
// Loads take a single cycle, so there is no acknowledgement signal.
// `latch_line_in` is expected to be asserted for only a single cycle.
module linebuf_parallel_load
#(
    parameter PIX_WIDTH = 8,
    parameter LINE_WIDTH = 16,
    parameter KERN_WIDTH = 3
)
(
    input clk,
    input rst_n,
    input shift_en,
    input latch_line_in,
    input [LINE_WIDTH*PIX_WIDTH-1:0] line_in,
    output wire [PIX_WIDTH-1:0] pix_out,
    output wire [PIX_WIDTH*KERN_WIDTH-1:0] section_out,
    output wire buf_empty
);

reg [$clog2(LINE_WIDTH)-1:0] shifts_remaining;
wire [PIX_WIDTH-1:0] pixbuf_dins [0:LINE_WIDTH-1];
wire [PIX_WIDTH-1:0] pixbuf_douts [0:LINE_WIDTH-1];

genvar i;
generate
    for (i = 0; i < LINE_WIDTH; i = i + 1) begin
        if (i == 0) begin
            pixbuf_dins[i] = latch_line_in ? line_in[0 +: PIX_WIDTH] : 0;
        end else begin
            pixbuf_dins[i] = latch_line_in ? line_in[i*PIX_WIDTH +: PIX_WIDTH] : pixbuf_douts[i-1];
        end

        pixbuf #(.PIX_WIDTH(PIX_WIDTH)) pb_inst (
            .clk(clk),
            .rst_n(rst_n),
            .en(shift_en | latch_line_in),
            .din(pixbuf_dins[i]),
            .dout(pixbuf_douts[i])
        );
    end

    for (i = KERN_WIDTH; i > 0; i = i - 1)
        assign section_out[(KERN_WIDTH-i-1)*PIX_WIDTH +: PIX_WIDTH] = pixbuf_douts[LINE_WIDTH - i];
endgenerate

always @ (posedge clk) begin
    if (~rst_n)
        shifts_remaining <= 0;
    else begin
        if (latch_line_in)
            shifts_remaining <= LINE_WIDTH;
        else if (shift_en && shifts_remaining != 0)
            shifts_remaining <= shifts_remaining - 1;
    end
end

assign pix_out = pixbuf_douts[LINE_WIDTH - 1];
assign buf_empty = (shifts_remaining == 0);

endmodule
