`timescale 1ns / 1ps

module img_dma_iface
#(
    parameter PIX_WIDTH = 8,
    parameter IMG_WIDTH = 512,
    parameter IMG_HEIGHT = 512,
    parameter SEG_CNT_X = 4,
    parameter DMA_BASE_ADDR = 32'h41E0_0000 // Standard AXI DMA Base
)
(
    input wire rst_n,
    input wire clk,

    // Dispatcher Interface
    input wire                                          img_line_in_ready,
    input wire [$clog2(IMG_HEIGHT*SEG_CNT_X)-1:0]       img_line_in_idx,
    output reg                                          img_line_in_valid,
    output reg [(IMG_WIDTH/SEG_CNT_X)*PIX_WIDTH-1:0]    img_line_in,

    // AXI-Lite Master Interface (To DMA Control Registers)
    output reg  [31:0] m_axi_awaddr,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    output reg  [31:0] m_axi_wdata,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,

    // AXI-Stream Slave Interface (From DMA Data Port)
    input  wire [PIX_WIDTH-1:0] s_axis_tdata,
    input  wire                 s_axis_tvalid,
    output wire                 s_axis_tready,
    input  wire                 s_axis_tlast
);

// Internal Constants
localparam SEG_PIX_COUNT = IMG_WIDTH / SEG_CNT_X;
localparam BYTES_PER_SEG = SEG_PIX_COUNT * (PIX_WIDTH / 8);

// DMA Register Offsets (MM2S)
localparam REG_MM2S_DMACR  = DMA_BASE_ADDR + 32'h00;
localparam REG_MM2S_SA     = DMA_BASE_ADDR + 32'h18;
localparam REG_MM2S_LENGTH = DMA_BASE_ADDR + 32'h28;

// FSM States
reg [2:0] state;
localparam IDLE = 3'b000, WRITE_SA = 3'b001, WRITE_LEN = 3'b010, COLLECT_DATA = 3'b011, DONE = 3'b100;

reg [$clog2(SEG_PIX_COUNT):0] pix_cnt;

// Address Calculation
// Assumes 0-indexed memory start; add a base offset if necessary
wire [31:0] start_addr = img_line_in_idx * BYTES_PER_SEG;

// AXI Stream Ready logic: Ready when we are in the collection state
assign s_axis_tready = (state == COLLECT_DATA);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        img_line_in_valid <= 1'b0;
        img_line_in <= 0;
        pix_cnt <= 0;
        m_axi_awvalid <= 1'b0;
        m_axi_wvalid <= 1'b0;
        m_axi_bready <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                img_line_in_valid <= 1'b0;
                if (img_line_in_ready) begin
                    state <= WRITE_SA;
                end
            end

            // Step 1: Write Source Address to DMA
            WRITE_SA: begin
                m_axi_awaddr  <= REG_MM2S_SA;
                m_axi_awvalid <= 1'b1;
                m_axi_wdata   <= start_addr;
                m_axi_wvalid  <= 1'b1;
                m_axi_bready  <= 1'b1;

                if (m_axi_awready && m_axi_wready) begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                end

                if (m_axi_bvalid) begin
                    m_axi_bready <= 1'b0;
                    state <= WRITE_LEN;
                end
            end

            // Step 2: Write Length (This triggers the DMA transfer)
            WRITE_LEN: begin
                m_axi_awaddr  <= REG_MM2S_LENGTH;
                m_axi_awvalid <= 1'b1;
                m_axi_wdata   <= BYTES_PER_SEG;
                m_axi_wvalid  <= 1'b1;
                m_axi_bready  <= 1'b1;

                if (m_axi_awready && m_axi_wready) begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                end

                if (m_axi_bvalid) begin
                    m_axi_bready <= 1'b0;
                    pix_cnt <= 0;
                    state <= COLLECT_DATA;
                end
            end

            // Step 3: Shift data from Stream into the wide segment register
            COLLECT_DATA: begin
                if (s_axis_tvalid && s_axis_tready) begin
                    // Shift in pixels (little-endian style)
                    img_line_in <= {s_axis_tdata, img_line_in[ (SEG_PIX_COUNT*PIX_WIDTH)-1 : PIX_WIDTH ]};
                    pix_cnt <= pix_cnt + 1;

                    if (pix_cnt == SEG_PIX_COUNT - 1 || s_axis_tlast) begin
                        state <= DONE;
                    end
                end
            end

            DONE: begin
                img_line_in_valid <= 1'b1;
                state <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
