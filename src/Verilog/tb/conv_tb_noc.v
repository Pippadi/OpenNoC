`timescale 1ns / 1ps

`define BMP_HEADER_SIZE 1078
// `define BMP_HEADER_SIZE 13
`define IMG_WIDTH 512
`define IMG_HEIGHT 512
`define PIX_WIDTH 8
`define SEG_CNT_X 2
`define SEG_CNT_Y 2

module conv_tb_noc();

// Clock and reset
reg clk;
reg rst_n;

// File handles
integer input_file, output_file;
reg [`PIX_WIDTH-1:0] imgData;
integer i, j, idx;

// Image buffers
localparam BYTES_PER_LINE = (`IMG_WIDTH/`SEG_CNT_X) * `PIX_WIDTH / 8;
localparam DMA_BEATS_PER_LINE = BYTES_PER_LINE / 4; // 32-bit DMA bus
localparam TOTAL_LINES = `IMG_HEIGHT * `SEG_CNT_X;

reg [7:0] img_in_mem [0:TOTAL_LINES-1][0:BYTES_PER_LINE-1];
reg [7:0] img_out_mem [0:TOTAL_LINES-1][0:BYTES_PER_LINE-1];

// AXI MM2S interface (testbench as master, sending input data)
reg [31:0] mm2s_axis_tdata;
reg mm2s_axis_tvalid;
wire mm2s_axis_tready;
reg mm2s_axis_tlast;

// AXI S2MM interface (testbench as slave, receiving output data)
wire [31:0] s2mm_axis_tdata;
wire s2mm_axis_tvalid;
reg s2mm_axis_tready;
wire s2mm_axis_tlast;

// Control signals from noc_top
wire dma_read_ready;
wire [$clog2(TOTAL_LINES)-1:0] dma_read_line_idx;
wire img_line_out_valid;
wire [$clog2(TOTAL_LINES)-1:0] img_line_out_idx;
wire done;

// Instantiate noc_top
noc_top DUT (
    .rst_n(rst_n),
    .clk(clk),

    .mm2s_axis_tdata(mm2s_axis_tdata),
    .mm2s_axis_tvalid(mm2s_axis_tvalid),
    .mm2s_axis_tready(mm2s_axis_tready),
    .mm2s_axis_tlast(mm2s_axis_tlast),

    .s2mm_axis_tdata(s2mm_axis_tdata),
    .s2mm_axis_tvalid(s2mm_axis_tvalid),
    .s2mm_axis_tready(s2mm_axis_tready),
    .s2mm_axis_tlast(s2mm_axis_tlast),

    .dma_read_ready(dma_read_ready),
    .dma_read_line_idx(dma_read_line_idx),
    .img_line_out_valid(img_line_out_valid),
    .img_line_out_idx(img_line_out_idx),
    .done(done)
);

// Clock generation
initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

// Timeout
initial begin
    #25_000_000;  // 6ms timeout
    $display("[TB] Simulation timeout at %t", $time);
    $finish;
end

// ============================================================================
// MM2S Master - Feed input image data over AXI
// ============================================================================

reg mm2s_active;
reg [$clog2(DMA_BEATS_PER_LINE+1)-1:0] mm2s_beat_idx;
reg [$clog2(TOTAL_LINES)-1:0] mm2s_line_idx;
reg mm2s_clear;

always @(posedge clk) begin
    if (~rst_n) begin
        mm2s_axis_tvalid <= 0;
        mm2s_axis_tdata <= 0;
        mm2s_axis_tlast <= 0;
        mm2s_active <= 0;
        mm2s_beat_idx <= 0;
        mm2s_line_idx <= 0;
    end else begin
        // Start MM2S transfer when orchestrator requests a line
        if (dma_read_ready && !mm2s_active) begin
            mm2s_active <= 1;
            mm2s_line_idx <= dma_read_line_idx;
            mm2s_beat_idx <= 0;
        end else if (mm2s_active) begin
            mm2s_beat_idx <= mm2s_beat_idx + (mm2s_axis_tready & mm2s_axis_tvalid);

            if (mm2s_beat_idx == DMA_BEATS_PER_LINE) begin
                mm2s_axis_tvalid <= 0;
                mm2s_axis_tlast <= 0;
                mm2s_active <= 0;
            end else begin
                mm2s_axis_tvalid <= 1;
                mm2s_axis_tlast <= (mm2s_beat_idx == DMA_BEATS_PER_LINE - 1);
                mm2s_axis_tdata <= {img_in_mem[mm2s_line_idx][(mm2s_beat_idx)*4+0],
                    img_in_mem[mm2s_line_idx][(mm2s_beat_idx)*4+1],
                    img_in_mem[mm2s_line_idx][(mm2s_beat_idx)*4+2],
                    img_in_mem[mm2s_line_idx][(mm2s_beat_idx)*4+3]};
            end
        end
    end
end

// ============================================================================
// S2MM Slave - Receive output image data over AXI
// ============================================================================

reg [$clog2(DMA_BEATS_PER_LINE)-1:0] s2mm_beat_idx;
reg s2mm_line_complete;

always @(posedge clk) begin
    if (~rst_n) begin
        s2mm_axis_tready <= 1;
        s2mm_beat_idx <= BYTES_PER_LINE-1;
        s2mm_line_complete <= 0;
    end else begin
        // Always ready to accept data
        s2mm_axis_tready <= 1;
        s2mm_line_complete <= s2mm_axis_tlast;

        // Capture data when valid
        if (s2mm_axis_tvalid && s2mm_axis_tready) begin
            // Store the 4 bytes from this beat
            img_out_mem[img_line_out_idx][s2mm_beat_idx*4 + 3] <= s2mm_axis_tdata[7:0];
            img_out_mem[img_line_out_idx][s2mm_beat_idx*4 + 2] <= s2mm_axis_tdata[15:8];
            img_out_mem[img_line_out_idx][s2mm_beat_idx*4 + 1] <= s2mm_axis_tdata[23:16];
            img_out_mem[img_line_out_idx][s2mm_beat_idx*4 + 0] <= s2mm_axis_tdata[31:24];

            if (s2mm_axis_tlast) begin
                // End of line
                s2mm_beat_idx <= BYTES_PER_LINE-1;
                $display("[TB] S2MM: Received output line %d at time %t", img_line_out_idx, $time);
            end else begin
                s2mm_beat_idx <= s2mm_beat_idx - 1;
            end
        end
    end
end

// ============================================================================
// File I/O Control
// ============================================================================

initial begin
    $dumpfile("conv_tb_noc.fst");
    $dumpvars(0, conv_tb_noc);

    // Load input image from file
    $display("[TB] Loading input image from peppers512.bmp...");
    input_file = $fopen("../../../data/peppers512.bmp", "rb");
    // input_file = $fopen("../../../data/gray_64x64.pgm", "rb");
    if (input_file == 0) begin
        $display("[TB] ERROR: Could not open input file ../../../data/peppers512.bmp");
        $finish;
    end

    output_file = $fopen("../../../data/outputPeppers.bmp", "wb");
    // output_file = $fopen("../../../data/out_gray_64x64.pgm", "wb");
    if (output_file == 0) begin
        $display("[TB] ERROR: Could not open output file");
        $finish;
    end

    // Copy BMP header
    for (i = 0; i < `BMP_HEADER_SIZE; i = i + 1) begin
        $fscanf(input_file, "%c", imgData);
        $fwrite(output_file, "%c", imgData);
    end

    // Load image data
    for (i = 0; i < TOTAL_LINES; i = i + 1) begin
        for (j = 0; j < BYTES_PER_LINE; j = j + 1) begin
            $fscanf(input_file, "%c", imgData);
            img_in_mem[i][j] = imgData;
        end
    end
    $display("[TB] Image loaded: %d lines x %d bytes per line", TOTAL_LINES, BYTES_PER_LINE);

    // Reset
    rst_n = 0;
    #100;
    rst_n = 1;
    #100;

    $display("[TB] Simulation started at time %t", $time);
end

// Write output lines to file as they complete
always @(posedge clk) begin
    if (s2mm_line_complete) begin
        // Line just completed, write it
        $fseek(output_file, `BMP_HEADER_SIZE+img_line_out_idx*BYTES_PER_LINE, 0);
        for (idx = 0; idx < BYTES_PER_LINE; idx = idx + 1) begin
            $fwrite(output_file, "%c", img_out_mem[img_line_out_idx][idx]);
        end
        $display("[TB] Wrote output line %d to file", img_line_out_idx);
    end
end

// Monitor done signal
always @(posedge clk) begin
    if (done) begin
        $display("[TB] Done signal asserted at time %t", $time);
        #100;
        $fclose(input_file);
        $fclose(output_file);
        $display("[TB] Simulation complete!");
        $finish;
    end
end

endmodule
