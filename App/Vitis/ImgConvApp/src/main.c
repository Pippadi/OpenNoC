#include "xscugic.h"
#include "xaxidma.h"
#include "xgpio.h"
#include "xparameters.h"
#include "image.h"
#include "sleep.h"

#define DONE_BIT_LOC 20
#define IDX_WIDTH 10
#define IDX_MASK 0x3FF

#define PIX_WIDTH 1 // In bytes
#define SEG_CNT_X 2
#define IMG_WIDTH 512 // In pixels
#define IMG_HEIGHT 512
#define SEG_W_NOPAD ((IMG_WIDTH/SEG_CNT_X) * PIX_WIDTH)

#define READ_IRQ 61
#define WRITE_IRQ 62

volatile int read_flag = 0;
volatile int write_flag = 0;

__attribute__((aligned(32))) static u8 dma_op_buffer[IMAGE_LEN];

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

    status = XGpio_Initialize(&idx_gpio, XPAR_AXI_GPIO_0_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("GPIO initialization failed with code %d\r\n", status);
        // If status is 19 (XST_DEVICE_NOT_FOUND), the BSP doesn't recognize this address
        return -1;
    }
    XGpio_SetDataDirection(&idx_gpio, 1, 0xFFFFFFFF);
    XGpio_SetDataDirection(&idx_gpio, 2, 0x00000000);

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
    // 0x3 -> Trigger on rising edge (doesn't work)
    // 0x1 -> Trigger on high level
    XScuGic_SetPriorityTriggerType(&gic, READ_IRQ, 0x00, 0x1);
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


    //Xil_DCacheFlushRange((u64) image, IMAGE_LEN);
    Xil_DCacheFlushRange((u64) dma_op_buffer, IMAGE_LEN);

    xil_printf("Header copying and flushing done, resetting PL...\r\n");
    XGpio_DiscreteClear(&idx_gpio, 2, 0xFFFFFFFF); // Apply rst_n
    usleep(10000); // Sleep 10ms
    XGpio_DiscreteSet(&idx_gpio, 2, 0xFFFFFFFF);   // Release rst_n
    xil_printf("Reset PL\r\n");

    u32 idx_gpio_in;
    u32 read_idx, write_idx;

    while (!done) {
        idx_gpio_in = XGpio_DiscreteRead(&idx_gpio, 1);
        done = (idx_gpio_in >> DONE_BIT_LOC) & 0x1;
        //xil_printf("0x%X\r\n", idx_gpio_in);
        //usleep(200000);

        if (read_flag) {
            read_idx = idx_gpio_in & IDX_MASK;
            UINTPTR addr = (UINTPTR) (image + (read_idx*SEG_W_NOPAD));
            xil_printf("Seg line 0x%X requested\r\n", read_idx);
            status = XAxiDma_SimpleTransfer(&myDma, addr, SEG_W_NOPAD, XAXIDMA_DMA_TO_DEVICE);
            if (status != XST_SUCCESS) {
                xil_printf("DMA read failed with code %d\r\n", status);
                return -1;
            }

            while (XAxiDma_Busy(&myDma, XAXIDMA_DMA_TO_DEVICE));
            xil_printf("Line sent\r\n");
            read_flag = 0;
        }

        if (write_flag) {
            write_idx = (idx_gpio_in >> IDX_WIDTH) & IDX_MASK;
            xil_printf("Seg line 0x%X written\r\n", write_idx);
            UINTPTR addr = (UINTPTR) (dma_op_buffer + (write_idx*SEG_W_NOPAD));
            status = XAxiDma_SimpleTransfer(&myDma, addr, SEG_W_NOPAD, XAXIDMA_DEVICE_TO_DMA);
            if (status != XST_SUCCESS) {
                xil_printf("DMA write failed with code %d\r\n", status);
                return -1;
            }

            while (XAxiDma_Busy(&myDma, XAXIDMA_DEVICE_TO_DMA));
            Xil_DCacheInvalidateRange((u64) dma_op_buffer, IMAGE_LEN);
            write_flag = 0;
        }
    }

    xil_printf("Done!\r\n");
}
