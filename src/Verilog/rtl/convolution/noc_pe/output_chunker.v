`timescale 1ns/1ps

module output_chunker
#(
    PIX_WIDTH = 8,
    CHUNK_WIDTH = 4
)
(
    input rst_n,
    input clk,
    input pix_in_valid,
    input [PIX_WIDTH-1:0] pix_in,

    output reg [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_out,
    output reg chunk_out_valid,
    input chunk_out_ready
);

reg [$clog2(CHUNK_WIDTH)-1:0] staging_pix_cnt;
wire [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_staging;

genvar i;
generate
    // Doing it this way gets rid of an array out-of-bounds warning
    pixbuf #(.PIX_WIDTH(PIX_WIDTH)) PixZero (
        .rst_n(rst_n),
        .clk(clk),
        .en(pix_in_valid),
        .din(pix_in),
        .dout(chunk_staging[PIX_WIDTH-1:0])
    );

    for (i = 1; i < CHUNK_WIDTH; i = i + 1) begin
        pixbuf #(.PIX_WIDTH(PIX_WIDTH)) Pix (
            .rst_n(rst_n),
            .clk(clk),
            .en(pix_in_valid),
            .din(chunk_staging[(i-1)*PIX_WIDTH +: PIX_WIDTH]),
            .dout(chunk_staging[i*PIX_WIDTH +: PIX_WIDTH])
        );
    end
endgenerate

always @ (posedge clk) begin
    if (~rst_n) begin
        staging_pix_cnt <= 0;
        chunk_out <= {CHUNK_WIDTH{1'b0}};
        chunk_out_valid <= 0;
    end else begin
        if (pix_in_valid && staging_pix_cnt == CHUNK_WIDTH-1) begin
                chunk_out <= chunk_staging;
                staging_pix_cnt <= 0;
                chunk_out_valid <= 1;
        end else begin
                staging_pix_cnt <= staging_pix_cnt + pix_in_valid;
                chunk_out_valid <= chunk_out_valid & ~chunk_out_ready;
        end
    end
end

endmodule
