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
    input clear_chunk,
    output reg [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_out,
    output reg chunk_out_valid
);

reg [$clog2(CHUNK_WIDTH)-1:0] staging_pix_cnt;
wire [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_staging;

genvar i;
generate
    wire [PIX_WIDTH-1:0] chunk_staging_douts [0:CHUNK_WIDTH-1];

    for (i = 0; i < CHUNK_WIDTH; i = i + 1) begin
        pixbuf #(.PIX_WIDTH(PIX_WIDTH)) Pix (
            .rst_n(rst_n),
            .clk(clk),
            .en(pix_in_valid),
            .din(i == 0 ? pix_in : chunk_staging_douts[i-1]),
            .dout(chunk_staging_douts[i])
        );
    end
endgenerate

always @ (posedge clk) begin
    if (~rst_n) begin
        staging_pix_cnt <= 0;
        chunk_out <= {CHUNK_WIDTH{1'b0}};
        chunk_out_valid <= 0;
    end else begin
        if (pix_in_valid)
            if (staging_pix_cnt == CHUNK_WIDTH-1) begin
                chunk_out <= chunk_staging;
                staging_pix_cnt <= 0;
                chunk_out_valid <= 1;
            end else
                staging_pix_cnt <= staging_pix_cnt + 1;
        end else
            chunk_out_valid <= clear_chunk ? 0 : chunk_out_valid;
    end
end

endmodule
