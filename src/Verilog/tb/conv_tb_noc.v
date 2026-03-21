`timescale 1ns / 1ps

`define BMP_HEADER_SIZE 1080
`define IMG_WIDTH 512
`define IMG_HEIGHT 512
`define PIX_WIDTH 8

`define CHUNK_WIDTH 6
`define SEG_CNT_X 2
`define SEG_CNT_Y 1
`define NOC_X 4
`define NOC_Y 4

module conv_tb_noc();

reg clk;
reg rst_n;
reg [`PIX_WIDTH-1:0] imgData;
integer file, file1, i;

localparam SEG_WIDTH = `IMG_WIDTH / `SEG_CNT_X;
localparam SEG_HEIGHT = `IMG_HEIGHT / `SEG_CNT_Y;
localparam SEG_CNT_TOT = `SEG_CNT_X * `SEG_CNT_Y;

localparam LINE_WIDTH = SEG_WIDTH + 2; // +2 for halo pixels
localparam NOC_WIDTH = 2*($clog2(`NOC_X) + $clog2(`NOC_Y)) + $clog2(LINE_WIDTH/`CHUNK_WIDTH) + `CHUNK_WIDTH*`PIX_WIDTH;

reg [`IMG_WIDTH*`PIX_WIDTH:0] img [0:`IMG_HEIGHT-1];

// Map from PE index to segment index
// Most significant bit for idle, next bits for segment index, remaining bits for line index
localparam PE_MAP_WIDTH = 1 + $clog2(SEG_CNT_TOT) + $clog2(SEG_HEIGHT);
reg [PE_MAP_WIDTH-1:0] pe_segment_map [0:$clog2(`NOC_X)-1][0:$clog2(`NOC_Y)-1];

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

/*
// Timeout for infinite loop and short simulation runs when using dumpvars
initial begin
    #100000;
    $fclose(file);
    $fclose(file1);
    $finish;
end
*/

function automatic [LINE_WIDTH*`PIX_WIDTH-1:0] segment_line(input [`IMG_WIDTH*`PIX_WIDTH-1:0] img_line, input reg [$clog2(SEG_CNT_TOT)-1:0] seg_idx); begin
    segment_line[(LINE_WIDTH-1)*`PIX_WIDTH-1 : `PIX_WIDTH] = img_line[SEG_WIDTH*`PIX_WIDTH*(seg_idx % `SEG_CNT_X)-1 +: SEG_WIDTH*`PIX_WIDTH]; // Main segment pixels
    if (seg_idx % SEG_CNT_TOT == 0)
        segment_line[`PIX_WIDTH-1:0] = 0; // Right halo
    else
        segment_line[`PIX_WIDTH-1:0] = img_line[(seg_idx % `SEG_CNT_X - 1)*SEG_WIDTH*`PIX_WIDTH-1 -: `PIX_WIDTH]; // Right halo from previous segment
    if (seg_idx % `SEG_CNT_X == `SEG_CNT_X - 1)
        segment_line[LINE_WIDTH*`PIX_WIDTH-1 -: `PIX_WIDTH] = 0; // Left halo
    else
        segment_line[LINE_WIDTH*`PIX_WIDTH-1 -: `PIX_WIDTH] = img_line[SEG_WIDTH*`PIX_WIDTH*(seg_idx % `SEG_CNT_X + 1) +: `PIX_WIDTH]; // Left halo from next segment
end
endfunction

reg [$clog2(SEG_CNT_TOT)-1:0] next_seg;
reg [$clog2(`NOC_X)-1:0] pe_idx_x;
reg [$clog2(`NOC_Y)-1:0] pe_idx_y;
reg tx_chunk_ready;
wire [`CHUNK_WIDTH*`PIX_WIDTH-1:0] tx_chunk_out;
wire [$clog2(LINE_WIDTH/`CHUNK_WIDTH)-1:0] tx_chunk_idx;
wire tx_line_valid;
wire tx_chunk_valid, tx_line_complete;

line_chunker #(
    .PIX_WIDTH(`PIX_WIDTH),
    .LINE_WIDTH(LINE_WIDTH),
    .CHUNK_WIDTH(`CHUNK_WIDTH)
) LineChunker (
    .rst_n(rst_n),
    .clk(clk),
    .line_valid(tx_line_valid),
    .line_in(segment_line(img[pe_segment_map[pe_idx_x][pe_idx_y][$clog2(SEG_HEIGHT)-1:0]], next_seg)),
    .chunk_out_ready(tx_chunk_ready),
    .chunk_out(tx_chunk_out),
    .chunk_out_valid(tx_chunk_valid),
    .chunk_idx(tx_chunk_idx),
    .complete(tx_line_complete)
);

reg [7:0] line_temp [0:`IMG_WIDTH-1];
initial begin
    // Uncomment for value change dump
    /*
    $dumpfile("conv_tb_noc.vcd");
    $dumpvars(0, conv_tb_noc);
    $dumpvars(0, img[0]);
    */

    rst_n = 0;
    #100;
    rst_n = 1;
    #100;
    //file = $fopen("../../../../../../../data/gray_512x512.bmp", "rb");
    file = $fopen("../../../../../../../data/lena512.bmp", "rb");
    file1 = $fopen("../../../../../../../data/outputLena.bmp", "wb");
    //file = $fopen("../../../data/lena512.bmp","rb");       // Uncomment when
    //file1 = $fopen("../../../data/outputLena.bmp","wb");   // using Icarus Verilog
    for (i = 0; i < `BMP_HEADER_SIZE; i = i + 1) begin
        $fscanf(file, "%c", imgData);
        $fwrite(file1, "%c", imgData);
    end

    $fread(img, file);
    /*
    for (i = 0; i < `IMG_HEIGHT; i = i + 1) begin
        $fread(line_temp, file, 0, `IMG_WIDTH-1);
        for (integer j = 0; j < `IMG_WIDTH; j = j + 1) begin
            img[i][j*`PIX_WIDTH +: `PIX_WIDTH] = line_temp[j];
        end
    end
    */

    while (1) begin
        if (pe_idx_x == `NOC_X-1 && pe_idx_y == `NOC_Y-1 && pe_segment_map[pe_idx_x][pe_idx_y][PE_MAP_WIDTH-1] == 0) begin
            // All segments sent and processed
            $fclose(file);
            $fclose(file1);
            $finish;
        end
    end
end

reg [1:0] state;
localparam IDLE = 1'b0, SEND = 1'b1;
always @ (posedge clk) begin
    if (~rst_n) begin
        state <= IDLE;
        next_seg <= 0;
        next_seg = 0;
        pe_idx_x = 0;
        pe_idx_y = 0;
        for (i = 0; i < `NOC_X*`NOC_Y; i = i + 1) begin
            pe_segment_map[pe_idx_x][pe_idx_y] <= 0;
        end
    end else begin
        case (state)
        IDLE: begin
            if (pe_segment_map[pe_idx_x][pe_idx_y][PE_MAP_WIDTH-1] == 0) begin
                // Mark PE as busy, assign segment index, and preserve line index (incremented when line received by PE)
                pe_segment_map[pe_idx_x][pe_idx_y][PE_MAP_WIDTH-1] <= {1'b1, next_seg, pe_segment_map[pe_idx_x][pe_idx_y][$clog2(SEG_HEIGHT)-1:0]};
                state <= SEND;
            end else begin
                state <= IDLE;
                if (pe_idx_y == `NOC_Y - 1) begin
                    pe_idx_x <= (pe_idx_x == `NOC_X-1) ? 0 : pe_idx_x + 1;
                    pe_idx_y <= pe_idx_x == `NOC_X-1; // Address (0, 0) is the scheduler
                end else
                    pe_idx_y <= pe_idx_y + 1;
            end
        end

        SEND: state <= tx_line_complete ? IDLE : SEND;
        endcase
    end
end

assign tx_line_valid = (state == SEND);

always @ (posedge clk) tx_chunk_ready <= tx_chunk_valid;
wire [NOC_WIDTH-1:0] noc_out = (state == SEND) ? {4'b0, 4'b0, pe_idx_x, pe_idx_y, tx_chunk_idx, tx_chunk_out} : 0;
wire noc_out_valid = (state == SEND) ? tx_chunk_valid : 0;

endmodule
