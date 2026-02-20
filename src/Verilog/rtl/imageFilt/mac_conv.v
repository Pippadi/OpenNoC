`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.02.2026 21:28:12
// Design Name: 
// Module Name: mac_conv
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mac #(
    parameter INP_SIZE = 8,
    parameter OUT_SIZE = 16
) (
    input                         clk, rst, valid,
    input      [INP_SIZE - 1 : 0] op1, op2,
    output reg [OUT_SIZE - 1 : 0] aggregator
);
    
    always @(posedge clk) begin
        if (rst) begin
            aggregator <= 0;
        end 
        else begin
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
//     input      [TILE_SIZE * TILE_SIZE * 8 - 1 : 0] kernel, img,
//     input                                          clk, start,    // calculation begins at posedge of "start"
//     output reg                                     processing,    // this bit remains 1 while the calculation is in progress
//     output     [15:0]                              outPixel
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
//         .aggregator(outPixel)
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
//                 op1 <= kernel[(i*8) +: 8];
//                 op2 = img[(i*8) +: 8];
//                 i <= i + 1;
//             end
//         end
//     end

// endmodule


module conv_math #(
    parameter TILE_SIZE     = 3,
    parameter DIVISION_SIZE = 8
)(
    input      [TILE_SIZE*TILE_SIZE*8-1:0] kernel, img,
    input                                   clk, rst,
    input                                   start,
    output reg                              processing,
    output     [15:0]                       outPixel
);

    integer i;

    reg start_d;
    wire start_pulse;

    reg calc_start, mac_rst;
    reg [7:0] op1, op2;
    reg proc_started;

    assign start_pulse = start & ~start_d;

    // start edge detector
    always @(posedge clk) begin
        start_d <= start;
    end

    mac #(
        .INP_SIZE(8),
        .OUT_SIZE(16)
    ) M (
        .clk(clk),
        .rst(mac_rst),
        .valid(proc_started),
        .op1(op1),
        .op2(op2),
        .aggregator(outPixel)
    );

    always @(posedge clk) begin
        if (rst) begin
            calc_start <= 0;
            mac_rst    <= 1;
            processing <= 0;
            i <= 0;
        end
        else begin

            // start new operation
            if (start_pulse) begin
                mac_rst    <= 1;
                calc_start <= 0;
                i <= 0;
                processing <= 1;
                proc_started <= 0;
            end

            // release MAC reset after 1 cycle
            else if (processing && mac_rst) begin
                mac_rst <= 0;
                calc_start <= 1;
                proc_started <= 0;
            end

            // main compute loop
            else if (calc_start) begin
                if (i >= TILE_SIZE*TILE_SIZE) begin
                    calc_start <= 0;
                    processing <= 0;
                end
                else begin
                    proc_started <= 1;
                    op1 <= kernel[(i*8)+:8];
                    op2 <= img[(i*8)+:8];
                    i <= i + 1;
                end
            end

        end
    end

endmodule
