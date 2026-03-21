# NoC Processing Element (noc_pe)

This directory contains Verilog modules that adapt a convolution unit to the NoC by handling chunking, buffering, packetization, and NoC handshakes.

- `conv_pe.v` — Top-level processing element: bridges the NoC interface and local convolution logic, manages control and data flow, and instantiates buffering and chunking submodules.
- `line_chunk_buffer.v` — Reorders incoming chunks of a line so they can be loaded into the line buffer used by `conv_unit.v`.
- `output_chunker.v` — Output packetizer: collects convolution results into fixed-size chunks/packets, attaches framing metadata, and drives NoC transmit handshakes.