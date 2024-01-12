/*
Copyright (C) 2023, Advanced Micro Devices, Inc. All rights reserved.
SPDX-License-Identifier: MIT
*/
/***************************** Include Files *******************************/
#include "axi_1wire_host.h"
#include "xparameters.h"

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
void AXI_1WIRE_HOST_Reset(u32 baseaddr) {

    AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x80000000);

	return;
}
/**
 *
 * Performs the touch-bit function - write a 0 or 1 and reads the bus level.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *          bit is the level to write. To read the bus level, bit is set to 1
 *
 * @return  The level read
 * 
 */
u8 AXI_1WIRE_HOST_TouchBit(u32 baseaddr, u8 bit) {
	u8 val = 0;

	/* Wait for READY signal to be 1 to ensure 1-wire IP is ready */
    while((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x00000010) == 0){}

	if (bit)
		/* Read. Write read Bit command in register 0 */
		AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_INSTR_REG_OFFSET, AXI_1WIRE_HOST_READBIT);
	else
		/* Write. Write tx Bit command in instruction register with bit to transmit */
		AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_INSTR_REG_OFFSET, AXI_1WIRE_HOST_WRITEBIT + (bit & 0x01));

	/* Write Go signal and clear control reset signal in control register */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x00000001);

	/* Wait for done signal to be 1 */
	while((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x00000001) == 0){}

	/* If read, Retrieve data from register */
	if (bit)
		val = (u8)(AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_RXDATA_REG_OFFSET) & 0x00000001);

	/* Clear Go signal in register 1 */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x00000000);

	return val;
}

/**
 *
 * Performs the read-byte function.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *
 * @return  The value read
 * 
 */
u8 AXI_1WIRE_HOST_ReadByte(u32 baseaddr) {
	u8 val = 0;

	/* Wait for READY signal to be 1 to ensure 1-wire IP is ready */
    while((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x00000010) == 0){}

	/* Write read Byte command in register 0 */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_INSTR_REG_OFFSET, AXI_1WIRE_HOST_READBYTE);

	/* Write Go signal and clear control reset signal in control register */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x00000001);

	/* Wait for done signal to be 1 */
	while((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x00000001) == 0){}

	val = (u8)(AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_RXDATA_REG_OFFSET) & 0x000000FF);

	/* Clear Go signal in register 1 */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x00000000);

	return val;
}

/**
 *
 * Performs the write-byte function.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOSTinstance to be worked on.
 *          byte is the byte to write
 * 
 */
void AXI_1WIRE_HOST_WriteByte(u32 baseaddr, u8 byte) {

	/* Wait for READY signal to be 1 to ensure 1-wire IP is ready */
    while((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x00000010) == 0){}

	/* Write. Write tx Byte command in instruction register with bit to transmit */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_INSTR_REG_OFFSET, AXI_1WIRE_HOST_WRITEBYTE + (byte & 0xFF));

	/* Write Go signal and clear control reset signal in control register */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x00000001);

	/* Wait for done signal to be 1 */
	while((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x00000001) == 0){}

	/* Clear Go signal in register 1 */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x00000000);

	return;
}

/**
 *
 * Performs the Reset-Presence function.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *
 * @return  0=Device present, 1=No device present
 * 
 */
u8 AXI_1WIRE_HOST_ResetBus(u32 baseaddr) {
    u8 val = 0;

    /* Reset 1-wire Axi IP */
    AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, AXI_1WIRE_HOST_RESET);

	/* Wait for READY signal to be 1 to ensure 1-wire IP is ready */
    while((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x00000010) == 0){}

	/* Write Initialization command in instruction register */
    AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_INSTR_REG_OFFSET, AXI_1WIRE_HOST_INITPRES);

	/* Write Go signal and clear control reset signal in control register */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x00000001);

    /* Wait for done signal to be 1 */
	while((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x00000001) == 0){}

	/* Retrieve MSB bit in status register to get failure bit */
	if ((AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_STAT_REG_OFFSET) & 0x80000000) != 0)
		val = 1;

    /* Clear Go signal in register 1 */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_CTRL_REG_OFFSET, 0x00000000);

	return val;
}

/**
 *
 * Read the 1-Wire bus level. The 1-Wire bus is controlled through GPIO.
 *
 * @param   baseaddr is the base address of the AXI_1WIRE_HOST instance to be worked on.
 *
 * @return  Bus level
 * 
 */
u8 AXI_1WIRE_HOST_GPIO_Read(u32 baseaddr) {
	u8 val = 0;

    /* Configure the 1-Wire Host to read the 1-Wire Bus level */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_INSTR_REG_OFFSET, 0x80800000);

	/* Read the stored bus level */
    val = AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_GPIODATA_REG_OFFSET) & 0x00000001;

	return val;
}

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
void AXI_1WIRE_HOST_GPIO_Write(u32 baseaddr, u8 bit) {

    /* Configure the 1-Wire Host to write the 1-Wire Bus level */
	AXI_1WIRE_HOST_mWriteReg(baseaddr, AXI_1WIRE_HOST_INSTR_REG_OFFSET, (bit & 0x1) ? 0x80010000 : 0x80000000 );

	return;
}