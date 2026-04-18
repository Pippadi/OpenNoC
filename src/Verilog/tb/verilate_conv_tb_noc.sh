#!/bin/sh

shopt -s globstar

verilator -cc \
    conv_tb_noc.v \
    ../rtl/convolution/**/*.v \
    ../rtl/openNoc/src/*.v \
    --binary --trace-fst \
    -Wno-CASEX -Wno-CASEOVERLAP -Wno-CASEINCOMPLETE -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
    -j $(nproc) \
    && \

./obj_dir/Vconv_tb_noc
