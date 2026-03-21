# Image Convolution on a NoC

This folder contains three subfolders:
- `conv_unit`: This folder contains the Verilog code for the convolution unit, which performs the convolution operation on the input image using a specified kernel. The top module is `conv_unit.v`, which instantiates the necessary components to perform the convolution operation.
- `noc_pe`: This folder contains the Verilog code for the NoC processing element, which is responsible for connecting the convolution unit to the NoC. It handles all the required chunking, buffering, and handshaking.
- `noc_scheduler`: This folder contains the Verilog code for the scheduler, which segments the input image and dispatches work to the convolution units. For now, most of the scheduling logic is in the [testbench](/src/Verilog/tb/conv_tb_noc.v).
