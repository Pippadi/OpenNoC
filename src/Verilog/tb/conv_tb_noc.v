`timescale 1ns / 1ps

//`define BMP_HEADER_SIZE 11
`define BMP_HEADER_SIZE 1078
`define IMG_WIDTH 512
`define IMG_HEIGHT 512
`define PIX_WIDTH 8

// Most widths are in pixels, unless specified.

// Each PE processes a segment of the image. Each segment is fed line-by-line to the PEs.
// These lines are sent chunk-by-chunk over the NoC. Because NoC width is the ultimate parameter we want
// to optimize for, we parameterize the chunk width separately from the segment width.
// Segment width is calculated as (IMG_WIDTH / SEG_CNT_X) + (floor(KERN_X/2) * 4). Ensure CHUNK_WIDTH evenly
// divides segment width.
`define CHUNK_WIDTH 13 // In pixels
`define SEG_CNT_X 2
`define SEG_CNT_Y 2
`define NOC_X 2 // NoC X dimension (number of columns of PEs)
`define NOC_Y 2 // NoC Y dimension (number of rows of PEs)

`define KERN_X 3
`define KERN_Y 3

module conv_tb_noc();

reg clk;
reg rst_n;
reg [`PIX_WIDTH-1:0] imgData;
integer file, out_file, i, j, line_recvd_cnt;

reg [`IMG_WIDTH*`PIX_WIDTH-1:0] img [0:`IMG_HEIGHT-1];

localparam PADDING_X = (`KERN_X / 2) * 2;
localparam PADDING_Y = (`KERN_Y / 2) * 2;
localparam SEG_WIDTH = `IMG_WIDTH / `SEG_CNT_X + 2*PADDING_X;
localparam SEG_HEIGHT = `IMG_HEIGHT / `SEG_CNT_Y + 2*PADDING_Y;
localparam SEG_CNT_TOT = `SEG_CNT_X * `SEG_CNT_Y;
localparam NOC_BIT_WIDTH = 2*($clog2(`NOC_X)+$clog2(`NOC_Y)) + $clog2(SEG_WIDTH/`CHUNK_WIDTH) + `CHUNK_WIDTH*`PIX_WIDTH;

wire done;
// Input to dispatcher
wire [$clog2(`IMG_HEIGHT)-1:0] img_line_in_idx;
wire [31:0] recvd_chunk_cnt; // For testing, counts the number of chunks received by the dispatcher

// Output from reassembler
wire [$clog2(`IMG_HEIGHT*`SEG_CNT_X)-1:0] img_line_out_idx;
wire [(`IMG_WIDTH/`SEG_CNT_X)*`PIX_WIDTH-1:0] img_line_out;
wire img_line_out_valid;

// Directions are from the perspective of the PE
wire [`NOC_X*`NOC_Y-1:0] noc_out_valids;
wire [NOC_BIT_WIDTH*`NOC_X*`NOC_Y-1:0] noc_out_datas;
wire [`NOC_X*`NOC_Y-1:0] noc_out_readies;
wire [`NOC_X*`NOC_Y-1:0] noc_in_valids;
wire [NOC_BIT_WIDTH*`NOC_X*`NOC_Y-1:0] noc_in_datas;
wire [`NOC_X*`NOC_Y-1:0] noc_in_readies;

conv_pe_insts #(
    .PIX_WIDTH(`PIX_WIDTH),
    .NOC_X(`NOC_X),
    .NOC_Y(`NOC_Y),
    .IMG_WIDTH(`IMG_WIDTH),
    .IMG_HEIGHT(`IMG_HEIGHT),
    .CHUNK_WIDTH(`CHUNK_WIDTH),
    .SEG_CNT_X(`SEG_CNT_X),
    .SEG_CNT_Y(`SEG_CNT_Y)
) PE_Insts (
    .rst_n(rst_n),
    .clk(clk),

    .noc_out_valids(noc_out_valids),
    .noc_out_datas(noc_out_datas),
    .noc_out_readies(noc_out_readies),

    .noc_in_valids(noc_in_valids),
    .noc_in_datas(noc_in_datas),
    .noc_in_readies(noc_in_readies),

    // Orchestrator interfaces
    .img_line_in_idx(img_line_in_idx),
    .img_line_in(img[img_line_in_idx]),
    .img_line_out(img_line_out),
    .img_line_out_idx(img_line_out_idx),
    .img_line_out_valid(img_line_out_valid),

    // For testing
    .recvd_chunk_cnt(recvd_chunk_cnt),
        .done(done)
    );

    openNocTop #(
        .X(`NOC_X),
        .Y(`NOC_Y),
        .data_width(NOC_BIT_WIDTH-$clog2(`NOC_X)-$clog2(`NOC_Y)),
        .total_width(NOC_BIT_WIDTH),
        .if_width(NOC_BIT_WIDTH*`NOC_X*`NOC_Y),
        .pkt_no_field_size(0)
    ) NoC (
        .clk(clk),
        .rstn(rst_n),

        .r_data_pe(noc_out_datas),
        .r_valid_pe(noc_out_valids),
        .r_ready_pe(noc_out_readies),

        .w_ready_pe(noc_in_readies),
        .w_data_pe(noc_in_datas),
        .w_valid_pe(noc_in_valids)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    /*
    // Timeout for infinite loop and short simulation runs when using dumpvars
    initial begin
        #1000000;
        $fclose(file);
        $fclose(out_file);
        $finish;
    end
    */

    genvar x, y;
    generate
        for (x = 0; x < `NOC_X; x = x + 1) begin: map_x
            for (y = 0; y < `NOC_Y; y = y + 1) begin: map_y
                wire busy = PE_Insts.xs[0].ys[0].orchestrator.Orchestrator.pe_busies[x][y];
                wire [$clog2(SEG_CNT_TOT)-1:0] seg = PE_Insts.xs[0].ys[0].orchestrator.Orchestrator.pe_seg_map[x][y];
                wire [$clog2(SEG_HEIGHT)-1:0] seg_line = PE_Insts.xs[0].ys[0].orchestrator.Orchestrator.pe_seg_line_map[x][y];
            end
        end
    endgenerate

    reg [7:0] line_temp [0:`IMG_WIDTH-1];

    initial begin
        // Uncomment for value change dump
        /*
        $dumpfile("conv_tb_noc.fst");
        $dumpvars(0, conv_tb_noc);
        */

        //file = $fopen("../../../data/gray_8x8.pgm", "rb");
        //out_file = $fopen("../../../data/out_gray_8x8.pgm", "wb");
        //file = $fopen("../../../../../../../data/peppers512.bmp", "rb");
        //out_file = $fopen("../../../../../../../data/outputPeppers.bmp", "wb");
        file = $fopen("../../../data/peppers512.bmp","rb");       // Uncomment when
        out_file = $fopen("../../../data/outputPeppers.bmp","wb");   // using Icarus Verilog/Verilator
        for (i = 0; i < `BMP_HEADER_SIZE; i = i + 1) begin
            $fscanf(file, "%c", imgData);
            $fwrite(out_file, "%c", imgData);
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

        line_recvd_cnt = 0;
        while (1) begin
            @(posedge clk);
            if (img_line_out_valid) begin
                line_recvd_cnt = line_recvd_cnt + 1;
                $display("%d %x", img_line_out_idx, img_line_out);
                // Each output line corresponds to `IMG_WIDTH/`SEG_CNT_X pixels, need to account for BMP header and previous lines
                $fseek(out_file, `BMP_HEADER_SIZE + img_line_out_idx * (`IMG_WIDTH/`SEG_CNT_X) * `PIX_WIDTH/8, 0);
                for (i = 0; i < `IMG_WIDTH/`SEG_CNT_X; i = i + 1)
                    $fwrite(out_file, "%c", img_line_out[8*i +: 8]);
            end

            if (line_recvd_cnt == `IMG_HEIGHT*`SEG_CNT_X) begin
                $fclose(file);
                $fclose(out_file);
                $finish;
            end
        end
    end

endmodule
