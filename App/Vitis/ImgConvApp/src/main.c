#include "xscugic.h"
#include "xaxidma.h"
#include "xgpio.h"
#include "xparameters.h"
#include "image.h"

#define DONE_BIT_LOC 22
#define IDX_WIDTH 11
#define IDX_MASK 0x3FF // 11 bits high

#define PIX_WIDTH 1 // In bytes
#define SEG_CNT_X 4
#define IMG_WIDTH 512 // In pixels
#define IMG_HEIGHT 512
#define SEG_W_NOPAD (IMG_WIDTH/SEG_CNT_X) * PIX_WIDTH

#define READ_IRQ 61
#define WRITE_IRQ 62

volatile int read_flag = 0;
volatile int write_flag = 0;

void dma_read_isr(void*) {
    read_flag = 1;
}

void dma_write_isr(void*) {
    write_flag = 1;
}

int main() {
    XAxiDma_Config *myDmaConfig;
    XAxiDma myDma;
    XGpio idx_gpio;
    XScuGic gic;
    XScuGic_Config *gic_cfg;

    u32 done = 0;

    u32 status;

    xil_printf("Initializing peripherals\r\n");

    status = XGpio_Initialize(&idx_gpio, XPAR_XGPIO_0_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("GPIO initialization failed with code %d\r\n", status);
        // If status is 19 (XST_DEVICE_NOT_FOUND), the BSP doesn't recognize this address
        return -1;
    }
    XGpio_SetDataDirection(&idx_gpio, 1, 0xF); // Set to input. Is this necessary?

    myDmaConfig = XAxiDma_LookupConfig(XPAR_AXI_DMA_0_BASEADDR);
    if (XAxiDma_CfgInitialize(&myDma, myDmaConfig) != XST_SUCCESS) {
        xil_printf("DMA initialization failed\r\n");
        return -1;
    }

    gic_cfg = XScuGic_LookupConfig(XPAR_INTC_BASEADDR);
    if (gic_cfg == NULL) {
        xil_printf("Could not lookup GIC config\r\n");
        return -1;
    }

    status = XScuGic_CfgInitialize(&gic, gic_cfg, gic_cfg->CpuBaseAddress);
    if (status != XST_SUCCESS) {
        xil_printf("GIC initialization failed\r\n");
        return -1;
    }

    xil_printf("Initialized peripherals\r\n");

    // Set up interrupts
    // Connect GIC to exception handler
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler) XScuGic_InterruptHandler,
                                 &gic);
    Xil_ExceptionEnable();

    // 0x08 -> Lower priority than 0x0
    // 0x3 -> Trigger on rising edge
    XScuGic_SetPriorityTriggerType(&gic, READ_IRQ, 0x08, 0x1);
    XScuGic_SetPriorityTriggerType(&gic, WRITE_IRQ, 0x00, 0x1);

    /* Register interrupt handlers */
    XScuGic_Connect(&gic, READ_IRQ,
                    (Xil_InterruptHandler) dma_read_isr, NULL);
    XScuGic_Connect(&gic, WRITE_IRQ,
                    (Xil_InterruptHandler) dma_write_isr, NULL);

    /* Enable interrupts in GIC */
    XScuGic_Enable(&gic, READ_IRQ);
    XScuGic_Enable(&gic, WRITE_IRQ);
    // ---

    __attribute__((aligned(32))) static u8 dma_ip_buffer[IMAGE_LEN];
    __attribute__((aligned(32))) static u8 dma_op_buffer[IMAGE_LEN];

    memcpy(dma_op_buffer, dma_ip_buffer, HEADER_LEN); // Copy header from input to output

    Xil_DCacheFlushRange((u64) dma_ip_buffer, IMAGE_LEN);
    Xil_DCacheFlushRange((u64) dma_op_buffer, IMAGE_LEN);

    print("Header copying and flushing done\r\n");

    u32 idx_gpio_in;
    u32 read_idx, write_idx;

    while (!done) {
        idx_gpio_in = XGpio_DiscreteRead(&idx_gpio, 1);
        done = (idx_gpio_in >> DONE_BIT_LOC) & 0x1;

        if (read_flag) {
            read_idx = idx_gpio_in & IDX_MASK;
            xil_printf("Seg line %d requested\r\n", read_idx);
            status = XAxiDma_SimpleTransfer(&myDma, (UINTPTR) (dma_ip_buffer + (read_idx*SEG_W_NOPAD)), SEG_W_NOPAD, XAXIDMA_DMA_TO_DEVICE);
            if (status != XST_SUCCESS)
                return -1;

            while (XAxiDma_Busy(&myDma, XAXIDMA_DMA_TO_DEVICE));
            xil_printf("Line sent\r\n");
            read_flag = 0;
        }

        if (write_flag) {
            write_idx = (idx_gpio_in >> IDX_WIDTH) & IDX_MASK;
            xil_printf("Line ready\r\n");
            status = XAxiDma_SimpleTransfer(&myDma, (UINTPTR) (dma_op_buffer + (write_idx*SEG_W_NOPAD)), SEG_W_NOPAD, XAXIDMA_DEVICE_TO_DMA);
            if (status != XST_SUCCESS)
                return -1;

            while (XAxiDma_Busy(&myDma, XAXIDMA_DEVICE_TO_DMA));
            xil_printf("Line received\r\n");
            Xil_DCacheInvalidateRange((u64) dma_op_buffer, IMAGE_LEN);
            write_flag = 0;
        }
    }

    xil_printf("Done!\r\n");
}
