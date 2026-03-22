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
`define NOC_Y 1 // NoC Y dimension (number of rows of PEs)

module conv_tb_noc();

reg clk;
reg rst_n;
reg [`PIX_WIDTH-1:0] imgData;
integer file, file1, i, j;

localparam SEG_WIDTH = `IMG_WIDTH / `SEG_CNT_X;
localparam SEG_HEIGHT = `IMG_HEIGHT / `SEG_CNT_Y;
localparam SEG_CNT_TOT = `SEG_CNT_X * `SEG_CNT_Y;

localparam LINE_WIDTH = SEG_WIDTH + 2; // +2 for the halo pixels on each side. Assumes 3x3 kernel for now, parameterize later.
localparam NOC_WIDTH = 2*($clog2(`NOC_X) + $clog2(`NOC_Y)) + $clog2(LINE_WIDTH/`CHUNK_WIDTH) + `CHUNK_WIDTH*`PIX_WIDTH;

reg [`IMG_WIDTH*`PIX_WIDTH-1:0] img [0:`IMG_HEIGHT-1];

// Map from PE index to segment index
// Most significant bit for idle, next bits for segment index, remaining bits for line index
// Is there a better way to do this?
localparam PE_MAP_WIDTH = 1 + $clog2(SEG_CNT_TOT) + $clog2(SEG_HEIGHT);
reg [PE_MAP_WIDTH-1:0] pe_segment_map [0:`NOC_X-1][0:`NOC_Y-1];

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

// segment_line extracts the appropriate line segment with halo pixels for the given segment index.
// It handles edge cases for halo pixels by zero-padding when out of bounds.
function automatic [LINE_WIDTH*`PIX_WIDTH-1:0] segment_line(input [`IMG_WIDTH*`PIX_WIDTH-1:0] img_line, input reg [$clog2(SEG_CNT_TOT)-1:0] seg_idx); begin
    segment_line[`PIX_WIDTH +: `PIX_WIDTH*SEG_WIDTH] = img_line[SEG_WIDTH*`PIX_WIDTH*(seg_idx % `SEG_CNT_X) +: SEG_WIDTH*`PIX_WIDTH]; // Main segment pixels
    if (seg_idx % SEG_CNT_TOT == 0)
        segment_line[`PIX_WIDTH-1:0] = 0; // Right halo
    else
        segment_line[`PIX_WIDTH-1:0] = img_line[(seg_idx % `SEG_CNT_X - 1)*SEG_WIDTH*`PIX_WIDTH +: `PIX_WIDTH]; // Right halo from previous segment
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
wire [LINE_WIDTH*`PIX_WIDTH-1:0] current_segment_line = segment_line(img[pe_segment_map[pe_idx_x][pe_idx_y][$clog2(SEG_HEIGHT)-1:0]], next_seg);

line_chunker #(
    .PIX_WIDTH(`PIX_WIDTH),
    .LINE_WIDTH(LINE_WIDTH),
    .CHUNK_WIDTH(`CHUNK_WIDTH)
) LineChunker (
    .rst_n(rst_n),
    .clk(clk),
    .line_valid(tx_line_valid),
    .line_in(current_segment_line),
    .chunk_out_ready(tx_chunk_ready),
    .chunk_out(tx_chunk_out),
    .chunk_out_valid(tx_chunk_valid),
    .chunk_idx(tx_chunk_idx),
    .complete(tx_line_complete)
);

reg done;
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
        @ (posedge clk);
        if (done) begin
            // All segments sent and processed
            $fclose(file);
            $fclose(file1);
            $finish;
        end
    end
end

reg state;
localparam IDLE = 1'b0, SEND = 1'b1;
always @ (posedge clk) begin
    if (~rst_n) begin
        state <= IDLE;
        next_seg <= 0;
        next_seg <= 0;
        pe_idx_x <= 0;
        pe_idx_y <= 1;
        for (i = 0; i < `NOC_X; i = i + 1)
            for (j = 0; j < `NOC_Y; j = j + 1)
                pe_segment_map[i][j] <= {PE_MAP_WIDTH{1'b0}};

    end else begin
        case (state)
        IDLE: begin
            // Cycle through PEs to find an idle one, assign next segment, and move to SEND state. If no idle PE, stay in IDLE and check again next cycle.
            $display("PE %d, %d: %b", pe_idx_x, pe_idx_y, pe_segment_map[pe_idx_x][pe_idx_y]);
            if (pe_segment_map[pe_idx_x][pe_idx_y][PE_MAP_WIDTH-1] == 0) begin
                // Mark PE as busy, assign segment index, and preserve line index (incremented when line received by PE)
                pe_segment_map[pe_idx_x][pe_idx_y] <= {1'b1, next_seg, pe_segment_map[pe_idx_x][pe_idx_y][$clog2(SEG_HEIGHT)-1:0]};
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

        // line_chunker is active and sending chunks for the assigned segment. Once complete, return to IDLE state.
        SEND: begin
             if (tx_line_complete) begin
                 state <= IDLE;
                 next_seg <= next_seg + 1;
                 done <= next_seg == SEG_CNT_TOT-1;
             end
        end
        endcase
    end
end

assign tx_line_valid = (state == SEND);

/* For testing before connecting to the NoC */
reg tx_chunk_valid_prev;
always @ (posedge clk) begin
    if (~rst_n) begin
        tx_chunk_valid_prev <= 0;
        tx_chunk_ready <= 0;
    end else begin
        tx_chunk_valid_prev <= tx_chunk_valid;
        tx_chunk_ready <= tx_chunk_valid & ~tx_chunk_valid_prev;
    end
end
/********************************************/

wire [NOC_WIDTH-1:0] noc_out = (state == SEND) ? {4'b0, 4'b0, pe_idx_x, pe_idx_y, tx_chunk_idx, tx_chunk_out} : 0;
wire noc_out_valid = (state == SEND) ? tx_chunk_valid : 0;

endmodule
