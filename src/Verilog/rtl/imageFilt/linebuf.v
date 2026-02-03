module line_buffer(
    #(
    parameter PIX_WIDTH = 8,
    parameter LINE_WIDTH = 16,
    parameter KERN_WIDTH = 3
)
(
    input rst_n,
    input clk,
    input buf_in_valid,
    input [PIX_WIDTH*LINE_WIDTH-1:0] buf_in,
    input data_request,
    output wire [PIX_WIDTH*KERN_WIDTH-1:0] section_out,
    output wire data_available,
    output reg buf_in_ready
);

reg [PIX_WIDTH*LINE_WIDTH-1:0] line_buf;
reg [$clog2(LINE_WIDTH)-1:0] out_ptr;
reg data_latched;

// Extract the requested section from the line buffer
genvar i;
generate
    for (i = 0; i < KERN_WIDTH; i = i + 1)
        assign section_out[i*PIX_WIDTH+:PIX_WIDTH] = line_buf[out_ptr + i];
endgenerate

// Indicate if more data is available
assign data_available = (rst_n && data_latched && out_ptr <= LINE_WIDTH - KERN_WIDTH);

always @ (posedge clk) begin
    if (~rst_n) begin
        out_ptr <= 0;
        line_buf <= 0;
        buf_in_ready <= 0;
        data_latched <= 0;
    end else begin
        // Latch new data into the line buffer
        if (buf_in_valid && ~data_latched) begin
            line_buf <= buf_in;
            buf_in_ready <= 1;
            data_latched <= 1;
        end else begin
            buf_in_ready <= 0;
        end

        // Advance output pointer if data is requested
        if (data_latched && data_request && out_ptr < LINE_WIDTH - KERN_WIDTH)
            out_ptr <= out_ptr + 1;
    end
end

endmodule
