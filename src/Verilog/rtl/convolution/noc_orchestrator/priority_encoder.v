`timescale 1ns / 1ps

module priority_encoder
#(parameter N = 8)
(
    input wire [N-1:0] in,
    output reg [$clog2(N)-1:0] out
);

integer i;
reg found;

always @ (in) begin
    found = 0;
    out = 0;
    for (i = N-1; i >= 0; i = i - 1) begin
        if (in[i] & ~found) begin
            out = i;
            found = 1;
        end
    end
end

endmodule
