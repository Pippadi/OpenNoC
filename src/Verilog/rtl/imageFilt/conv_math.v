// The conv_math module performs convolution operation on the input pixel data
// and kernel data. The kernel and pixel data is expected to be read in a row-major order.
module conv_math
#(
    parameter PIX_WIDTH = 8,
    parameter KERN_WIDTH = 3,
    parameter KERN_HEIGHT = 3
)
(
    input clk,
    input rst_n,
    input en,
    input [KERN_WIDTH*KERN_HEIGHT*PIX_WIDTH-1:0] kern,
    input [KERN_WIDTH*KERN_HEIGHT*PIX_WIDTH-1:0] pix_in,
    output wire [PIX_WIDTH-1:0] pix_out,
    output reg pix_out_valid
);

integer i;
reg [2*PIX_WIDTH-1:0] multData [0:KERN_WIDTH*KERN_HEIGHT-1];
reg [2*PIX_WIDTH-1:0] sumData;
reg multDataValid;

always @ (posedge clk) begin
    if (~rst_n) begin
        pix_out_valid <= 1'b0;
        for (i=0; i < KERN_WIDTH*KERN_HEIGHT; i = i + 1)
            multData[i] <= 0;
    end else begin
        if (en) begin
            for (i=0; i < KERN_WIDTH*KERN_HEIGHT; i = i + 1)
                multData[i] <= kern[i*PIX_WIDTH+:PIX_WIDTH] * pix_in[i*PIX_WIDTH+:PIX_WIDTH];
        end
        pix_out_valid <= en;
    end
end


always @ (*) begin
    sumData = 0;
    for(i=0;i<KERN_WIDTH*KERN_HEIGHT;i=i+1)
        sumData = sumData + multData[i];
end

assign pix_out = sumData/(KERN_WIDTH*KERN_HEIGHT);

endmodule

