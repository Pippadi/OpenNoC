module linebuf
#(
    parameter PIX_WIDTH = 8,
    parameter LINE_WIDTH = 16,
    parameter KERN_WIDTH = 3
)
(
    input clk,
    input rst_n,
    input shift_en,
    input [PIX_WIDTH-1:0] pix_in,
    output wire [PIX_WIDTH-1:0] pix_out,
    output wire [PIX_WIDTH*KERN_WIDTH-1:0] section_out
);

wire [PIX_WIDTH-1:0] pixbuf_dins [0:LINE_WIDTH-1];
wire [PIX_WIDTH-1:0] pixbuf_douts [0:LINE_WIDTH-1];

genvar i;
generate
    for (i = 0; i < LINE_WIDTH; i = i + 1) begin
        if (i == 0)
            assign pixbuf_dins[i] = pix_in;
        else
            assign pixbuf_dins[i] = pixbuf_douts[i-1];

        pixbuf #(.PIX_WIDTH(PIX_WIDTH)) pb_inst (
            .clk(clk),
            .rst_n(rst_n),
            .en(shift_en),
            .din(pixbuf_dins[i]),
            .dout(pixbuf_douts[i])
        );
    end

    for (i = KERN_WIDTH; i > 0; i = i - 1) begin
        assign section_out[(KERN_WIDTH-i)*PIX_WIDTH +: PIX_WIDTH] = pixbuf_douts[LINE_WIDTH - i];
    end
endgenerate

assign pix_out = pixbuf_douts[LINE_WIDTH-1];

endmodule
