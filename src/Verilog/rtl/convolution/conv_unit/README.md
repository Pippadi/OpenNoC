# conv_unit

Short, technical descriptions of files in this directory:

- `conv_unit.v` - Top-level convolution unit: coordinates line buffers, triggers convolution math, outputs one pixel per valid cycle, and asserts `line_req` when the top line buffer needs a new line.
- `linebuf.v` - Serial line buffer built from `pixbuf` elements: shifts pixels on `shift_en` and exposes the KERN_WIDTH-rightmost window as `section_out`.
- `linebuf_parallel_load.v` - Parallel-load line buffer: accepts a full `line_in` on `latch_line_in`, supports subsequent serial shifting, exposes the KERN_WIDTH-rightmost window and a `buf_empty` flag indicating readiness for a new load.
- `pixbuf.v` - Single-pixel register bank (PIX_WIDTH DFFs) with enable `en`; used as the storage element in line buffers.
- `mac.v` - Multiply-accumulate cell: when `valid` is asserted accumulates `op1 * op2` into `aggregator`.
- `mac_conv.v` (module `conv_math`) - Convolution controller: sequences MAC operations across kernel elements, applies fixed-point right-shift by `KERN_FRAC_BITS`, and produces `pix_out` with `pix_out_valid`.
