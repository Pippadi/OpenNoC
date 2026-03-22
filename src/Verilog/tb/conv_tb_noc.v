`timescale 1ns / 1ps

`define BMP_HEADER_SIZE 1078
`define IMG_WIDTH 512
`define IMG_HEIGHT 512
`define PIX_WIDTH 8

// Most widths are in pixels, unless specified.

// Each PE processes a segment of the image. Each segment is fed line-by-line to the PEs.
// These lines are sent chunk-by-chunk over the NoC. Because NoC width is the ultimate parameter we want
// to optimize for, we parameterize the chunk width separately from the segment width.
// LINE_WIDTH is calculated as SEG_WIDTH+2 below to account for halo pixels. Ensure that CHUNK_WIDTH divides LINE_WIDTH.
`define CHUNK_WIDTH 6 // In pixels
`define SEG_CNT_X 2
`define SEG_CNT_Y 1
`define NOC_X 4 // NoC X dimension (number of columns of PEs)
`define NOC_Y 2 // NoC Y dimension (number of rows of PEs)

module conv_tb_noc();

reg clk;
reg rst_n;
reg [`PIX_WIDTH-1:0] imgData;
integer file, file1, i, j;

reg [`IMG_WIDTH*`PIX_WIDTH-1:0] img [0:`IMG_HEIGHT-1];

localparam SEG_WIDTH = `IMG_WIDTH / `SEG_CNT_X;
localparam SEG_HEIGHT = `IMG_HEIGHT / `SEG_CNT_Y;
localparam SEG_CNT_TOT = `SEG_CNT_X * `SEG_CNT_Y;
localparam LINE_WIDTH = SEG_WIDTH + 2; // +2 for the halo pixels on each side. Assumes 3x3 kernel for now, parameterize later.
localparam NOC_BIT_WIDTH = 2*($clog2(`NOC_X)+$clog2(`NOC_Y)) + $clog2(LINE_WIDTH/`CHUNK_WIDTH) + `CHUNK_WIDTH*`PIX_WIDTH;

wire done;
reg noc_out_ready;
wire [NOC_BIT_WIDTH-1:0] noc_out_data;
wire noc_out_valid;
wire [$clog2(`IMG_HEIGHT)-1:0] img_line_idx;

conv_dispatcher #(
    .PIX_WIDTH(`PIX_WIDTH),
    .NOC_X(`NOC_X),
    .NOC_Y(`NOC_Y),
    .IMG_WIDTH(`IMG_WIDTH),
    .IMG_HEIGHT(`IMG_HEIGHT),
    .CHUNK_WIDTH(`CHUNK_WIDTH),
    .SEG_CNT_X(`SEG_CNT_X),
    .SEG_CNT_Y(`SEG_CNT_Y)
) Dispatcher (
    .rst_n(rst_n),
    .clk(clk),
    .img_line_idx(img_line_idx),
    .img_line_in(img[img_line_idx]),
    .noc_out_ready(noc_out_ready),
    .noc_out_data(noc_out_data),
    .noc_out_valid(noc_out_valid),
    .done(done)
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

// Timeout for infinite loop and short simulation runs when using dumpvars
initial begin
    #50000;
    $fclose(file);
    $fclose(file1);
    $finish;
end

reg [7:0] line_temp [0:`IMG_WIDTH-1];
initial begin
    // Uncomment for value change dump
    $dumpfile("conv_tb_noc.vcd");
    $dumpvars(0, conv_tb_noc);

    //file = $fopen("../../../../../../../data/gray_512x512.bmp", "rb");
    file = $fopen("../../../../../../../data/lena512.bmp", "rb");
    file1 = $fopen("../../../../../../../data/outputLena.bmp", "wb");
    //file = $fopen("../../../data/lena512.bmp","rb");       // Uncomment when
    //file1 = $fopen("../../../data/outputLena.bmp","wb");   // using Icarus Verilog
    for (i = 0; i < `BMP_HEADER_SIZE; i = i + 1) begin
        $fscanf(file, "%c", imgData);
        $fwrite(file1, "%c", imgData);
    end

    // Have to do this, because $fread's count argument is too small to read all of it at once
    for (i = 0; i < `IMG_HEIGHT; i = i + 1) begin
        $fread(line_temp, file, 0, `IMG_WIDTH);
        for (j = 0; j < `IMG_WIDTH; j = j + 1) begin
            img[i][j*`PIX_WIDTH +: `PIX_WIDTH] = line_temp[j];
        end

    end

    rst_n = 0;
    #100;
    rst_n = 1;
    #100;

    while (1) begin
        @(posedge clk);
        if (done) begin
            // All segments sent and processed
            $fclose(file);
            $fclose(file1);
            $finish;
        end
    end
end

/* For testing before connecting to the NoC */
reg noc_out_valid_prev;
always @ (posedge clk) begin
    if (~rst_n) begin
        noc_out_valid_prev <= 0;
        noc_out_ready <= 0;
    end else begin
        noc_out_valid_prev <= noc_out_valid;
        noc_out_ready <= noc_out_valid & ~noc_out_valid_prev;
    end
end
/********************************************/


endmodule
