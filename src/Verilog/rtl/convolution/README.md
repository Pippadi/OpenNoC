# Image Convolution on a NoC

This folder contains three subfolders:
- `conv_unit`: This folder contains the Verilog code for the convolution unit, which performs the convolution operation on the input image using a specified kernel. The top module is `conv_unit.v`, which instantiates the necessary components to perform the convolution operation.
- `noc_pe`: This folder contains the Verilog code for the NoC processing element, which is responsible for connecting the convolution unit to the NoC. It handles all the required chunking, buffering, and handshaking.
- `noc_orchestrator`: This folder contains the Verilog code for the scheduler (which we call a dispatcher to avoid naming conflicts), which segments the input image and dispatches work to the convolution units. The reassembly logic will go here once implemented.

`conv_pe_insts.v` instantiates the convolution PEs and orchestrator, to be used with the [OpenNoC top module](/src/Verilog/rtl/openNoc/src/openNocTop.v).
