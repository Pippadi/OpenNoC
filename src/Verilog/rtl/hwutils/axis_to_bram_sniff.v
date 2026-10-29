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

    output reg we,
    output reg [DATA_WIDTH-1:0] w_data,
    output reg [$clog2(IMG_WIDTH*IMG_HEIGHT/(DATA_WIDTH/8))-1:0] w_addr
);

localparam SEG_WIDTH_NOPAD = IMG_WIDTH / SEG_CNT_X;
localparam WORD_CNT_PER_LINE = SEG_WIDTH_NOPAD/(DATA_WIDTH/PIX_WIDTH);

reg [$clog2(WORD_CNT_PER_LINE)-1:0] word_cnt;

always @(posedge clk) begin
    if (~rst_n) begin
        word_cnt <= 0;
        we <= 0;
    end else begin
        if (s_axis_tvalid & s_axis_tready) begin
            we <= 1;
            word_cnt <= (word_cnt == WORD_CNT_PER_LINE-1) ? 0 : word_cnt + 1;
            w_addr <= (line_no << $clog2(WORD_CNT_PER_LINE)) | word_cnt; // only works if WORD_CNT_PER_LINE is a power of 2, good enough for now
            w_data <= s_axis_tdata;
        end else
            we <= 0;
    end
end

endmodule
