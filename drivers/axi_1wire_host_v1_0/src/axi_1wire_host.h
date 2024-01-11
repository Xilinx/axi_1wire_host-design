/*
Copyright (C) 2023, Advanced Micro Devices, Inc. All rights reserved.
SPDX-License-Identifier: MIT
*/
#ifndef AXI_1WIRE_HOST_H
#define AXI_1WIRE_HOST_H


/****************** Include Files ********************/
#include "xil_types.h"
#include "xstatus.h"
#include "xparameters.h"
#include "xil_io.h"

#define AXI_1WIRE_HOST_INSTR_REG_OFFSET 0x0
#define AXI_1WIRE_HOST_CTRL_REG_OFFSET 0x4
#define AXI_1WIRE_HOST_IRQCTRL_REG_OFFSET 0x8
#define AXI_1WIRE_HOST_STAT_REG_OFFSET 0xC
#define AXI_1WIRE_HOST_RXDATA_REG_OFFSET 0x10
#define AXI_1WIRE_HOST_GPIODATA_REG_OFFSET 0x14
#define AXI_1WIRE_HOST_IPVER_REG_OFFSET 0x18
#define AXI_1WIRE_HOST_IPID_REG_OFFSET 0x1C

#define AXI_1WIRE_HOST_INITPRES	0x0800
#define AXI_1WIRE_HOST_READBIT	0x0C00
#define AXI_1WIRE_HOST_WRITEBIT	0x0E00
#define AXI_1WIRE_HOST_READBYTE	0x0D00
#define AXI_1WIRE_HOST_WRITEBYTE	0x0F00
#define AXI_1WIRE_HOST_RESET    0x80000000

/**************************** Type Definitions *****************************/
/**
 *
 * Write a value to a AXI_1WIRE_HOST register. A 32 bit write is performed.
 * If the component is implemented in a smaller width, only the least
 * significant data is written.
 *
 * @param   BaseAddress is the base address of the AXI_1WIRE_HOSTdevice.
 * @param   RegOffset is the register offset from the base to write to.
 * @param   Data is the data written to the register.
 *
 * @return  None.
 *
 * @note
 * C-style signature:
 * 	void AXI_1WIRE_HOST_mWriteReg(void * baseaddr_pess, unsigned RegOffset, u32 Data)
 *
 */
#define AXI_1WIRE_HOST_mWriteReg(BaseAddress, RegOffset, Data) \
  	Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))

/**
 *
 * Read a value from a AXI_1WIRE_HOST register. A 32 bit read is performed.
 * If the component is implemented in a smaller width, only the least
 * significant data is read from the register. The most significant data
 * will be read as 0.
 *
 * @param   BaseAddress is the base address of the AXI_1WIRE_HOST device.
 * @param   RegOffset is the register offset from the base to write to.
 *
 * @return  Data is the data from the register.
 *
 * @note
 * C-style signature:
 * 	u32 AXI_1WIRE_HOST_mReadReg(void * baseaddr_pess, unsigned RegOffset)
 *
 */
#define AXI_1WIRE_HOST_mReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))

/************************** Function Prototypes ****************************/
/************************** Function Definitions ***************************/
/**
 *
 * Reset the 1-Wire Microcontroller.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *
 * @return
 * 
 */
void AXI_1WIRE_HOST_Reset(u32 baseaddr);

/**
 *
 * Performs the touch-bit function - write a 0 or 1 and reads the bus level.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *          bit is the level to write
 *
 * @return  The level read
 * 
 */
u8 AXI_1WIRE_HOST_TouchBit(u32 baseaddr, u8 bit);

/**
 *
 * Performs the read-byte function.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *
 * @return  The value read
 * 
 */
u8 AXI_1WIRE_HOST_ReadByte(u32 baseaddr);

/**
 *
 * Performs the write-byte function.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOSTinstance to be worked on.
 *          byte is the byte to write
 * 
 */
void AXI_1WIRE_HOST_WriteByte(u32 baseaddr, u8 byte);

/**
 *
 * Performs the Reset-Presence function.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *
 * @return  0=Device present, 1=No device present
 * 
 */
u8 AXI_1WIRE_HOST_ResetBus(u32 baseaddr);

/**
 *
 * Run a self-test on the driver/device. Note this may be a destructive test if
 * resets of the device are performed.
 *
 * If the hardware system is not built correctly, this function may never
 * return to the caller.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *
 * @return
 *
 *    - XST_SUCCESS   if all self-test code passed
 *    - XST_FAILURE   if any self-test code failed
 *
 * @note    Caching must be turned off for this function to work.
 * @note    Self test may fail if data memory and device are not on the same bus.
 *
 */
XStatus AXI_1WIRE_HOST_SelfTest(u32 baseaddr);

/**
 *
 * Read the 1-Wire bus level. The 1-Wire bus is controlled through GPIO.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *
 * @return  Bus level
 * 
 */
u8 AXI_1WIRE_HOST_GPIO_Read(u32 baseaddr);

/**
 *
 * Set the 1-Wire bus level. The 1-Wire bus is controlled through GPIO.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 * 			bit is the bus level
 *
 * @return
 * 
 */
void AXI_1WIRE_HOST_GPIO_Write(u32 baseaddr, u8 bit);

#endif // AXI_1WIRE_HOST_H