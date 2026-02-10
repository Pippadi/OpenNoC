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
    input [PIX_WIDTH-1:0] pin,
    output wire [PIX_WIDTH-1:0] pout,
    output wire [PIX_WIDTH*KERN_WIDTH-1:0] section_out
);

wire [PIX_WIDTH-1:0] pixbuf_douts [0:LINE_WIDTH-1];

integer i;
generate
    for (i = 0; i < LINE_WIDTH; i = i + 1) begin
        if (i == 0) begin
            pixbuf #(.PIX_WIDTH(PIX_WIDTH)) pb_inst (
                .clk(clk),
                .rst_n(rst_n),
                .en(shift_en),
                .din(pin),
                .dout(pixbuf_douts[i])
            );
        end else if (i == LINE_WIDTH - 1) begin
            pixbuf #(.PIX_WIDTH(PIX_WIDTH)) pb_inst (
                .clk(clk),
                .rst_n(rst_n),
                .en(shift_en),
                .din(pixbuf_douts[i-1]),
                .dout(pout)
            );
        end else begin
            pixbuf #(.PIX_WIDTH(PIX_WIDTH)) pb_inst (
                .clk(clk),
                .rst_n(rst_n),
                .en(shift_en),
                .din(pixbuf_douts[i-1]),
                .dout(pixbuf_douts[i])
            );
        end
    end

    for (i = KERN_WIDTH; i > 0; i = i - 1)
        assign section_out[(KERN_WIDTH-i-1)*PIX_WIDTH +: PIX_WIDTH] = pixbuf_douts[LINE_WIDTH - i];
endgenerate

endmodule
