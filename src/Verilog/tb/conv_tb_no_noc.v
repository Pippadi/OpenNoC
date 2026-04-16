`timescale 1ns / 1ps

`define headerSize 1080
`define imageSize 512*512

module conv_tb();

reg clk;
reg reset;
reg [7:0] imgData;
integer file, file1, i;
reg lineValid;
integer sentSize;
wire [7:0] outData;
wire outDataValid;
wire lineRequested;
integer receivedData = 0;

reg [7:0] convolvedLine [0:511];

reg [7:0] lineUnpacked [0:511];
wire [512*8-1:0] linePacked;
genvar j;
generate
    for (j = 0; j < 512; j = j + 1) begin
        assign linePacked[j*8 +: 8] = lineUnpacked[j];
    end
endgenerate

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

initial begin
    // Uncomment for value change dump
    /*
    $dumpfile("conv_tb.vcd");
    $dumpvars(0, conv_tb);
    */

   reset = 0;
   sentSize = 0;
   lineValid = 0;
   #100;
   reset = 1;
   #100;
   //file = $fopen("../../../../../../../data/gray_512x512.bmp", "rb");
   file = $fopen("../../../../../../../data/peppers512.bmp", "rb");
   file1 = $fopen("../../../../../../../data/outputPeppers.bmp", "wb");
   //file = $fopen("../../../data/peppers512.bmp","rb");       // Uncomment when
   //file1 = $fopen("../../../data/outputPeppers.bmp","wb");   // using Icarus Verilog
   for (i = 0; i < `headerSize; i = i + 1) begin
       $fscanf(file, "%c", imgData);
       $fwrite(file1, "%c", imgData);
   end

   lineValid = 1'b0;
   while (sentSize < `imageSize) begin
       @(posedge clk);
       if (lineRequested) begin
           // Read a line of pixel data into lineUnpacked
           $fread(lineUnpacked, file, 0, 512);
           lineValid = 1'b1;
           // Keep lineValid high until lineRequested goes low
           while (lineRequested) begin
               @(posedge clk);
               lineValid = lineRequested;
           end
           sentSize = sentSize + 512;
       end
   end

   //@(posedge clk);
   //lineValid = 1'b0;
   $fclose(file);
   while(1) begin
       @(posedge clk);
       imgData = 0;
       lineValid = 1'b0;
   end
end

integer k;
always @(posedge clk) begin
    if (outDataValid) begin
        receivedData = receivedData + 1;
        convolvedLine[receivedData % 512] = outData;
        if (receivedData % 512 == 511) begin
            for (k = 511; k >= 0; k = k - 1) begin
                $fwrite(file1, "%c", convolvedLine[k]);
            end
        end
    end

    // -1 as sim stops at 39999
    if (receivedData == `imageSize - 1) begin
        $fclose(file1);
        $finish;
    end
end

conv_unit #(
    .PIX_WIDTH(8),
    .LINE_WIDTH(512),
    .KERN_FRAC_BITS(6),
    .KERN_WIDTH(3),
    .KERN_HEIGHT(3)
) conv_unit_inst (
    .clk(clk),
    .rst_n(reset),
    .kern({8'd7, 8'd7, 8'd7,
    8'd7, 8'd7, 8'd7,
    8'd7, 8'd7, 8'd7}), // Box blur kernel
    .line_in(linePacked),
    .latch_line_in(lineValid),
    .pix_out(outData),
    .line_req(lineRequested),
    .pix_out_valid(outDataValid)
);

endmodule
