/*
Copyright (C) 2023, Advanced Micro Devices, Inc. All rights reserved.
SPDX-License-Identifier: MIT
*/
/***************************** Include Files *******************************/
#include "axi_1wire_host.h"
#include "xparameters.h"
#include "stdio.h"
#include "xil_io.h"

/************************** Constant Definitions ***************************/
/************************** Function Definitions ***************************/
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
XStatus AXI_1WIRE_HOST_SelfTest(u32 baseaddr)
{
	u32 ip_id;
	u32 ip_ver;

	xil_printf("******************************\n\r");
	xil_printf("* AXI 1-Wire Host Self Test\n\r");
	xil_printf("* Reading IP ID and IP version\n\r");

	ip_id = AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_IPID_REG_OFFSET);
	ip_ver = AXI_1WIRE_HOST_mReadReg(baseaddr, AXI_1WIRE_HOST_IPVER_REG_OFFSET);

	if(ip_id != 0x10EE4453){
		xil_printf("Error, the IP ID does not correspond to the AXI 1-Wire Host ID.\n\rExpected 0x10EE_4453, read 0x%x\n\r", ip_id);
		return XST_FAILURE;
	}
	if(((ip_ver >> 24) & 0xFF) != 0x76){
		xil_printf("Error, the IP version read does not match the expected format\n\r");
		return XST_FAILURE;		
	}
	xil_printf("* IP Subsystem vendor ID is 0x%x\n\r* ID is 0x%x\n\r", ((ip_id >> 16) & 0xFFFF), (ip_id & 0xFFFF));
	xil_printf("* IP version is %x.%x\n\r", ((ip_ver >> 8) & 0xFFFF), (ip_ver & 0xFF));
	xil_printf("******************************\n\n\r");

	return XST_SUCCESS;
}
