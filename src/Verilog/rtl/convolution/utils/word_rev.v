`timescale 1ns / 1ps

module word_rev
#(
    parameter W_CNT = 4,
    parameter W_WIDTH = 8
)
(
    input wire [W_CNT*W_WIDTH-1:0] data_in,
    output wire [W_CNT*W_WIDTH-1:0] data_out
);

genvar i;
generate
    for (i = 0; i < W_CNT; i = i + 1) begin : byte_rev_gen
        assign data_out[i*W_WIDTH +: W_WIDTH] = data_in[(W_CNT-1-i)*W_WIDTH +: W_WIDTH];
    end
endgenerate

endmodule
