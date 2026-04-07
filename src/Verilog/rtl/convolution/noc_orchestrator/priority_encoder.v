`timescale 1ns / 1ps

module priority_encoder
#(parameter N = 8)
(
    input wire [N-1:0] in,
    output reg [$clog2(N)-1:0] out
);

integer i;

always @ (in) begin
    for (i = N-1; i >= 0; i = i - 1) begin
        if (in[i]) begin
            out = i;
            break;
        end
    end
end

endmodule
