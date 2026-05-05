#!/bin/sh

shopt -s globstar

verilator -cc \
    conv_tb_noc.v \
    ../rtl/convolution/**/*.v \
    ../rtl/openNoc/src/*.v \
    --binary --trace-fst \
    --top-module conv_tb_noc \
    --threads 4 \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
    -j $(nproc) \
    && \

    ./obj_dir/Vconv_tb_noc
