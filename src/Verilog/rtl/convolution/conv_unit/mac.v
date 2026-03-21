`timescale 1ns / 1ps

module mac
#(
    parameter INP_SIZE = 8,
    parameter OUT_SIZE = 16
)
(
    input                         clk, rst, valid,
    input      [INP_SIZE - 1 : 0] op1, op2,
    output reg [OUT_SIZE - 1 : 0] aggregator
);

always @(posedge clk) begin
    if (rst) begin
        aggregator <= 0;
    end else begin
        if (valid) begin
            aggregator <= aggregator + (op1 * op2);
        end
    end
end

endmodule
