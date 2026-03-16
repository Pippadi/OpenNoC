`timescale 1ns / 1ps

module conv_pe
#(
    parameter PIX_WIDTH = 8,
    parameter NOC_ADDR_X = 1,
    parameter NOC_ADDR_Y = 1,
    parameter NOC_ADDR_X_WIDTH = 4,
    parameter NOC_ADDR_Y_WIDTH = 4,
    parameter LINE_WIDTH = 16,
    parameter CHUNK_WIDTH = 4,

    localparam NOC_DATA_WIDTH = 2*(NOC_ADDR_X_WIDTH+NOC_ADDR_Y_WIDTH) + $clog2(LINE_WIDTH/CHUNK_WIDTH) + CHUNK_WIDTH*PIX_WIDTH
)
(
    input wire clk,
    input wire rst_n,
    input wire noc_data_in_valid,
    input wire [NOC_DATA_WIDTH-1:0] noc_data_in,
    output reg [NOC_DATA_WIDTH-1:0] noc_data_out,
    output wire noc_data_ready
);


reg conv_latch_line;
wire conv_pix_valid;
wire conv_line_req;
wire [PIX_WIDTH-1:0] conv_pix;

wire [LINE_WIDTH*PIX_WIDTH-1:0] line;
reg chunkbuf_line_clear;
wire chunkbuf_line_valid;
reg chunkbuf_chunk_avail;

wire [$clog2(LINE_WIDTH/CHUNK_WIDTH)-1:0] chunk_idx_in = noc_data_in[2*(NOC_ADDR_X_WIDTH+NOC_ADDR_Y_WIDTH)-1 -: $clog2(LINE_WIDTH/CHUNK_WIDTH)];
wire [CHUNK_WIDTH*PIX_WIDTH-1:0] chunk_in = noc_data_in[0 +: CHUNK_WIDTH*PIX_WIDTH];

assign noc_data_ready = chunkbuf_chunk_avail;

line_chunk_buffer #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(LINE_WIDTH),
    .CHUNK_WIDTH(CHUNK_WIDTH)
) LineChunkBuffer (
    .rst_n(rst_n),
    .clk(clk),
    .chunk_avail(chunkbuf_chunk_avail),
    .chunk_idx(chunk_idx_in),
    .chunk(chunk_in),
    .line_clear(chunkbuf_line_clear),
    .line(line),
    .line_valid(chunkbuf_line_valid)
);

conv_unit #(
    .PIX_WIDTH(PIX_WIDTH),
    .LINE_WIDTH(LINE_WIDTH),
    .KERN_FRAC_BITS(6),
    .KERN_WIDTH(3),
    .KERN_HEIGHT(3)
) ConvUnit (
    .clk(clk),
    .rst_n(rst_n),
    .kern({8'd7, 8'd7, 8'd7,
    8'd7, 8'd7, 8'd7,
    8'd7, 8'd7, 8'd7}), // Box blur kernel, hardcoded for now
    .line_in(line),
    .latch_line_in(conv_latch_line),
    .pix_out(conv_pix),
    .line_req(conv_line_req),
    .pix_out_valid(conv_pix_valid)
);

// State machine to load the conv unit when it requests a line and the chunk buffer is valid,
// then clear the chunk buffer afterwards
localparam [1:0] S_IDLE  = 2'd0, S_LATCH = 2'd1;

reg [1:0] state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        conv_latch_line <= 1'b0;
        chunkbuf_line_clear <= 1'b0;
        chunkbuf_chunk_avail <= 1'b0;
    end else begin
        case (state)
            S_IDLE: begin
                // Wait for conv unit request and a valid line from the chunk buffer
                chunkbuf_line_clear <= 1'b0;
                chunkbuf_chunk_avail <= noc_data_in_valid;
                if (conv_line_req && chunkbuf_line_valid) begin
                    // Pulse latch for one cycle to load the line into the convolution unit
                    conv_latch_line <= 1'b1;
                    state <= S_LATCH;
                end else begin
                    conv_latch_line <= 1'b0;
                    state <= S_IDLE;
                end
            end

            S_LATCH: begin
                chunkbuf_line_clear <= 1'b1;  // Clear the chunk buffer for the next line
                chunkbuf_chunk_avail <= 1'b0; // Make sure clearing the buffer happens first
                conv_latch_line <= 1'b0;
                state <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
                conv_latch_line <= 1'b0;
                chunkbuf_line_clear <= 1'b0;
                chunkbuf_chunk_avail <= 1'b0;
            end
        endcase
    end
end

endmodule
