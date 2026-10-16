module axis_to_bram_sniff
#(
    parameter DATA_WIDTH = 32,
    parameter SEG_CNT_X = 2,
    parameter IMG_WIDTH = 512,
    parameter IMG_HEIGHT = 512,
    parameter PIX_WIDTH = 8
)
(
    input rst_n,
    input clk,

    input [$clog2(IMG_HEIGHT*SEG_CNT_X)-1:0] line_no,

    input s_axis_tvalid,
    input s_axis_tready,
    input [DATA_WIDTH-1:0] s_axis_tdata,

    output wire we,
    output wire [DATA_WIDTH-1:0] w_data,
    output wire [$clog2(IMG_WIDTH*IMG_HEIGHT/(DATA_WIDTH/8))-1:0] w_addr
);

localparam SEG_WIDTH_NOPAD = IMG_WIDTH / SEG_CNT_X;

assign we = s_axis_tready & s_axis_tvalid;

reg [$clog2(SEG_WIDTH_NOPAD)-1:0] pix_cnt;
assign w_addr = (line_no << $clog2(SEG_WIDTH_NOPAD)) | pix_cnt; // only works if SEG_WIDTH_NOPAD is a power of 2, good enough for now

always @(posedge clk) begin
    if (~rst_n) begin
        pix_cnt <= 0;
    end else begin
        if (we) begin
            pix_cnt <= (pix_cnt == SEG_WIDTH_NOPAD-1) ? 0 : pix_cnt + 1;
        end
    end
end

endmodule
