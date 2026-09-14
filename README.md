# OpenNoc (Work-in-Progress)

OpenNoC is an open-source network-on-chip implementation following a deflection-routed toroidal topology.

This project builds upon the work done [here](https://github.com/kuladeepsaireddy/OpenNoc).

![Convolution-blurred Peppers](data/outputPeppers.bmp)

At present, an image convolution processing element (PE) has been written as a proof-of-concept workload for the NoC.
A scheduler/orchestrator has been implemented to segment an image, dispatch segments to PEs on the NoC for convolution, and reassemble the final image.
Hardware implementation on a Zynq-7000 FPGA is in progress.
Simulation output for 3x3 box blurred Peppers image shown above.

## Directory structure

The project is under heavy development, and older/unused code hasn't been removed from the project yet.

**App**: Vivado and Vitis projects. `ImgConv` is where the latest work is being done.

**data**: Directory where the testing image for image processing application is located.
The output after processing is also stored in the same directory.

**src**: Contains RTL sources for the NoC, convolution PEs, and testbenches.

Some subfolders have READMEs with more information.

## Getting Started

### Simulation

Simulation of the orchestrator, NoC, and convolution cores can be done with [`conv_tb_noc`](src/Verilog/tb/conv_tb_noc.v).
Use the shell script in the same directory to Verilate the RTL and run simulation.
Modify the testbench following the notes in the comments.

### Implementation

Use `ImgConv` in `App/Vivado` and `App/Vitis`.
