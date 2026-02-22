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

module conv_math
#(
    parameter PIX_WIDTH = 8,
    parameter KERN_FRAC_BITS = 4,
    parameter KERN_WIDTH = 3,
    parameter KERN_HEIGHT = 3
)
(
    input                                   clk, rst_n,
    input [KERN_WIDTH*KERN_HEIGHT*PIX_WIDTH-1:0] kern, img,
    input                                   en,
    output reg  [PIX_WIDTH-1:0]             pix_out,
    output wire                             pix_out_valid
);

reg [1:0] state;
localparam IDLE = 0, PROCESSING = 1, DONE = 2;
integer i;

wire mac_ops_valid = (state == PROCESSING) && (i <= (KERN_WIDTH*KERN_HEIGHT));
wire mac_rst = (state == IDLE) | ~rst_n;
wire [2*PIX_WIDTH-1:0] mac_out;
assign pix_out_valid = (state == DONE);
wire [PIX_WIDTH-1:0] op1 = kern[(i*PIX_WIDTH)+:PIX_WIDTH];
wire [PIX_WIDTH-1:0] op2 = img[(i*PIX_WIDTH)+:PIX_WIDTH];

mac #(
    .INP_SIZE(PIX_WIDTH),
    .OUT_SIZE(2*PIX_WIDTH)
) MAC_UNIT (
    .clk(clk),
    .rst(mac_rst),
    .valid(mac_ops_valid),
    .op1(op1),
    .op2(op2),
    .aggregator(mac_out)
);

always @(posedge clk) begin
    if (~rst_n) begin
        state <= IDLE;
        pix_out <= 0;
        i <= 0;
    end else begin
        case (state)
            IDLE: begin
                state <= en ? PROCESSING : IDLE;
                pix_out <= 0;
                i <= 0;
            end
            PROCESSING: begin
                if (i < KERN_WIDTH*KERN_HEIGHT-1) begin
                    i <= i + 1;
                end else begin
                    state <= DONE;
                    pix_out <= mac_out >> KERN_FRAC_BITS; // Adjust for fixed-point scaling
                end
            end
            DONE: state <= en ? DONE : IDLE;
        endcase
    end
end

endmodule
