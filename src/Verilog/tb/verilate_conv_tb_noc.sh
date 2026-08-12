#!/bin/sh

shopt -s globstar

verilator -cc \
    conv_tb_noc.v \
    ../rtl/convolution/conv_unit/*.v \
    ../rtl/convolution/noc_pe/*.v \
    ../rtl/convolution/noc_orchestrator/*.v \
    ../rtl/convolution/noc_top.v \
    ../rtl/convolution/img_dma_iface.v \
    ../rtl/convolution/conv_pe_insts.v \
    ../rtl/openNoc/src/*.v \
    --binary --trace-fst \
    --top-module conv_tb_noc \
    --threads 2 \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
    -j $(nproc) \
    && \

    ./obj_dir/Vconv_tb_noc
