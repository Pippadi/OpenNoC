`timescale 1ns / 1ps

// A buffer for a pixel. Basically a PIX_WIDTH array of DFFs.
module pixbuf
#(
    parameter PIX_WIDTH = 8
)
(
    input clk,
    input rst_n,
    input en,
    input [PIX_WIDTH-1:0] din,
    output reg [PIX_WIDTH-1:0] dout
);

always @(posedge clk) begin
    if (~rst_n)
        dout <= 0;
    else if (en)
        dout <= din;
end

endmodule
