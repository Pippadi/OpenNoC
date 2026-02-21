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

// module conv_math #(
//     parameter TILE_SIZE     = 3,
//     parameter DIVISION_SIZE = 8
// ) (
//     input      [TILE_SIZE * TILE_SIZE * 8 - 1 : 0] kern, img,
//     input                                          clk, start,    // calculation begins at posedge of "start"
//     output reg                                     processing,    // this bit remains 1 while the calculation is in progress
//     output     [15:0]                              pix_out
// );

//     integer i;

//     reg       calc_start, mac_rst, pre_start;
//     reg [7:0] op1, op2;

//     mac #(
//         .INP_SIZE(8),
//         .OUT_SIZE(16)
//     ) M (
//         .clk(clk), .rst(mac_rst), .valid(calc_start),
//         .op1(op1), .op2(op2),
//         .aggregator(pix_out)
//     );

//     always @(posedge start) begin
//         pre_start  <= 1'b1;
//         mac_rst    <= 1'b1;
//     end

//     always @(negedge start) begin
//         if (pre_start == 1'b1) begin
//             pre_start  <= 1'b0;
//             calc_start <= 1'b1;
//             mac_rst    <= 1'b0;
//             i <= 0;
//         end
//     end

//     always @(posedge clk) begin
//         if (calc_start) begin
//             if (i >= TILE_SIZE * TILE_SIZE) begin
//                 calc_start <= 1'b0;
//                 processing <= 1'b0;
//                 calc_start <= 1'b0;
//             end
//             else begin
//                 processing <= 1'b1;
//                 op1 <= kern[(i*8) +: 8];
//                 op2 = img[(i*8) +: 8];
//                 i <= i + 1;
//             end
//         end
//     end

// endmodule


module conv_math
#(
    parameter PIX_WIDTH = 8,
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
wire [PIX_WIDTH-1:0] mac_out;
assign pix_out_valid = (state == DONE);
wire [PIX_WIDTH-1:0] op1 = kern[(i*PIX_WIDTH)+:PIX_WIDTH];
wire [PIX_WIDTH-1:0] op2 = img[(i*PIX_WIDTH)+:PIX_WIDTH];

mac #(
    .INP_SIZE(PIX_WIDTH),
    .OUT_SIZE(PIX_WIDTH) // Make sure this is wider later
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
                    pix_out <= mac_out;
                end
            end
            DONE: state <= en ? DONE : IDLE;
        endcase
    end
end

endmodule
