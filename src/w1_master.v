/*
Copyright (C) 2023, Advanced Micro Devices, Inc. All rights reserved.
SPDX-License-Identifier: MIT
*/
/*
-------------------------------------------------------------------------------
-- Title      : 1-Wire master
-- Project    : 1-wire
-------------------------------------------------------------------------------
-- File       : w1_master.v
-- Author     : Thomas Delev thomasd@amd.com
-- Company    : Advanced Micro Devices, Inc.
-- Created    : 2023/06/05
-- Last update: 2023/06/05
-- Copyright  : (c) Advanced Micro Devices, Inc. 2023
-------------------------------------------------------------------------------
-- Uses       : jcnt.v, sr.v
-------------------------------------------------------------------------------
-- Description: The master sub-module to drive initialization, bit and byte
--              transmission and receiving with one or more 1-wire devices.
--
--              When communicate with the 1-wire devices, this module acts as
--              the master to send and receive bits to the 1-wire bus in
--              order to execute the initialization (reset and presence
--              pulse), to send bit and byte and to receive bit and bytes.
--              
--              This module read a register to get 4 bits instructions and a
--              byte to transmit then output 2 control signals and a data byte
--              The module output the following control signal and data byte:
--                Done: signal command executed
--                Ready: signal master is ready for next instruction
--                Failure: signal initialization failed
--                data_out: data received from 1-wire bus
--
--              For more  information about 1-wire devices, please refer to 
--              your specific 1-wire device. For general information about
--              1-wire, you can refer to the Dallas Semiconductior datasheet
--              at: 
--          analog.com/media/en/technical-documentation/data-sheets/ds18b20.pdf
--
-- Inputs/Outpus
--              clk_1MHz    : 1 MHz (1us period) input clock;
--              areset      : asynchronous reset from AXI register;
--              ctrl_reset  : reset control issue by PS in one of the AXI register, MSB in register 1
--              go          : PS signal to initiate the command execution, LSB in register 1;
--              command     : 4 MSB in register 0 issued by PS;
--              tx_data     : 8 LSB in register 0 to be send to device (tx_bit is LSB);
--              
--              dq          : 1-Wire Bus;
--              
--              done        : LSB Bit in register 2, set to 1 once command execution completed;
--              reg_wr      : Master signal to control write in AXI registers;
--              failure     : MSB Bit in register 2, set to 1 if no device detected;
--              data_out    : 8 LSB in register 3 received from device (rx_bit is LSB);
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  	Description
-- 2023/06/05  0.1      thomasd     Initial Version
-- 2023/06/06  0.2      thomasd     Cleanup
-- 2023/08/14  0.3      thomasd     Removal of unused functions
-- 2023/08/23  0.4      thomasd     Fix bug releated to DONE
-- 2024/02/07  0.5      thomasd     Fix 50KHz clock
-------------------------------------------------------------------------------
*/
/*
Commands:

Name        Register value  Description
INIT_M      1000            Reset/Initialization state: 1-wire initialization sequence, 
                                master send reset pulse and received presence pulse. Once
                                the sequence is completed, the done signal is set to 1. If
                                a presence pulse is not detected, the failure signal is set
                                to 1 .Once done, move to DONE_M state.
RX_BIT_M    1100            Receive bit state: master read a bit from 1-wire and output
                                it in the lsb of data_out. When completed, done
                                is set to 1. Once done, move to DONE_M state.
RX_BYTE_M   1101            Receive byte state: master read 8 bits from 1-wire and 
                                output it to data_out. When completed, done is
                                set to 1. Once done, move to DONE_M state.
TX_BIT_M    1110            Transmit bit state: master send 1 bit to 1-wire. Once
                                done, set done to 1 and move to DONE_M state.
                                LSB from tx_data is transmitted.
TX_BYTE_M   1111            Transmit byte state: master send 8 bits to 1-wire. Once
                                done, set done to 1 and move to DONE_M state.
                                tx_data are transmitted.
*/
/*
    HANDSHAKE SEQUENCE
    1. PS signal go (1) to initiate the command execution
    2. PL signal done (1) to signal to PS execution completed and register content available
    3. PS clear go (0) once register content has been read
    4. PL signal ready (1) to indicate it is ready for next command
    1. PS signal go (1) to initiate next command execution
*/

module W1_MASTER (
    input   wire        clk_1MHz,
    input   wire        areset,
    input   wire        ctrl_reset,
    input   wire        go,
    input   wire [3:0]  command,    // 4 MSB in register 0 issued by PS
    input   wire [7:0]  tx_data,    // 8 LSB in register 0 to be send to device (tx_bit is LSB)
    
    input   wire        from_dq,    // data from one-wire bus
    // inout               dq,         // 1-Wire Bus
    output  reg         dq_ctrl,    // registered version of read_write_dq
    output  reg         dq_out,    // registered version of to_dq
    
//    output reg [3:0] PRESENT_STATE,
    output  reg         done,       // Initialization done
    output  reg         ready,      // Ready for next instruction
    output  reg         reg_wr,     // Initialization failed, no devices found on 1-wire
    output  reg         failure,    // 1 bit received, can be read in data_out[0]
    output  reg [7:0]   data_out   // data received from 1-wire
);
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Invert reset signal
wire reset = !areset | ctrl_reset;          // active high reset signal
// reg and wire
reg         to_dq;          // data to one-wire bus
reg         read_write_dq;  // if 0 then dq <= to_dq (write) if 1 then from_dq <= dq (read)
reg         from_dq_pp;     // data of presence pulse 0 if presence pulse is detected.


wire [9:0]  jc1_q;
reg         jc1_reset;
wire        clk_50KHz;

reg         jc2_reset;
wire [1:0]  jc2_q;

wire        ts_60_to_80us;
wire        ts_0_to_10us;
wire        ts_0_to_1us;
wire        ts_14_to_15us;

reg [7:0]   data_RX; // Store the data comming from one-wire

reg         sr1_reset;
reg         sr1_en;
wire [7:0]  sr1_q;
reg         sr2_reset;
reg         sr2_en;
wire [6:0]  sr2_q;

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// define the state machine state
reg [3:0] PRESENT_STATE;
reg [3:0] NEXT_STATE;

parameter [3:0]
// Only commands that should be in the MEM
INIT_M      = 4'b1000,   // Reset/Initialization state
TX_BIT_M    = 4'b1110,   // Transmit bit to device
TX_BYTE_M   = 4'b1111,   // Transmit byte to device
RX_BIT_M    = 4'b1100,   // Receive bit from device
RX_BYTE_M   = 4'b1101,   // Receive byte from device
// Should not be found it the MEM, used for the FSM
DONE_M      = 4'b0100,   // Done state, after every state, wait for PS to clear Go.
IDLE_M      = 4'b0001,   // Idle state, increment memory address value, reset signal, transition between every state
TX_RST_PLS  = 4'b0010,   // Transmit Reset Pulse state
RX_PRE_PLS  = 4'b0011;   // Receive Presence Detect state


initial begin
    PRESENT_STATE <= IDLE_M;
end

always @ (posedge clk_1MHz or posedge reset) begin
    if (reset) begin
        PRESENT_STATE <= IDLE_M;
    end
    else begin
        PRESENT_STATE <= NEXT_STATE;        
    end
end
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*
  -------------------------------------------------------------------
  -- Bidirectional iobuffer to control the direction of data flow on
  -- the one-wire bus
  -------------------------------------------------------------------  
*/
// IOBUF IOBUF1(
//     .O(from_dq), 
//     .IO(dq), 
//     .I(dq_out), 
//     .T(dq_ctrl)
// ); 
always @ (negedge clk_1MHz) begin
    dq_ctrl <= read_write_dq;
    dq_out <= to_dq;
end
always @ (posedge clk_50KHz or posedge reset) begin
    if (reset) begin
        from_dq_pp = 1'b1;                                  // default to NOT present
    end
    else if (PRESENT_STATE == RX_PRE_PLS & sr2_q[6] & ts_60_to_80us) begin  // second 60us slot in RX_PRE_PLS
        from_dq_pp = from_dq;                               // capture the presence bit
    end
end
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// ------------------------ Clock generation ------------------------ //
/*
  -------------------------------------------------------------------
  -- Johnson Counter 1
  -- (1) Use this counter to generate 20 us slow clock (jc2_q[9]).
  -- (2) It is also used to divide a period of time into time slots.
  --     It counts for small time slot which
  --     is 1 us wide, add up to total 20 slots. 
  -- It should be synchronized with JCount1.
  -------------------------------------------------------------------
*/
JCNT #(.COUNTER_WIDTH(10)) jc_1us_20us (
    .clk(clk_1MHz),
    .reset(reset | jc1_reset),
    .en(1'b1),
    .q(jc1_q)
);
/*
  -------------------------------------------------------------------
  -- 50 KHz slow clock based on JC1 msb
  -- use "not" here to generate rising
  -- edge at proper position
  -------------------------------------------------------------------
*/
assign  clk_50KHz = !jc1_q[9];
/*
  -------------------------------------------------------------------
  -- Johnson Counter 1 2
  -- This Johnson counter is used to deal with the time slots.
  -- It chops one state into small time slots. Each is 20 us long,
  -- total 4 slots.
  -- It's driven by the slow clock (20us) in this system.
  -- Counter transitions 00 -> 01 -> 11 -> 10 -> 00
  -------------------------------------------------------------------
*/
JCNT #(.COUNTER_WIDTH(2)) jc_20us_80us (
    .clk(clk_50KHz),
    .reset(reset | jc1_reset | jc2_reset),  // As jc2 is synchronised with jc1, a reset of jc1 should reset jc2
    .en(1'b1),
    .q(jc2_q)
);
/*                               
  -------------------------------------------------------------------
  -- Several time slot identification signals
  -------------------------------------------------------------------
  -- Suppose the beginning of each state is time 0.
  -- Use combination of JC1 and JC2, we can id any time slot during
  -- each state as small as 1 us.
*/

assign  ts_0_to_1us    = (!jc2_q[1] & !jc2_q[0] & !jc1_q[9] & !jc1_q[0]);
assign  ts_0_to_10us   = (!jc2_q[1] & !jc2_q[0] & !jc1_q[9]);
assign  ts_14_to_15us  = (!jc2_q[1] & !jc2_q[0] &  jc1_q[4] & !jc1_q[3]);  
assign  ts_60_to_80us  = ( jc2_q[1] & !jc2_q[0]);
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*
  -------------------------------------------------------------------
  -- Shift Register 1 
  -- Used to count 8 bits in a byte of data
  -------------------------------------------------------------------
*/
SR #(.REGISTER_WIDTH(8)) SR1 (
    .clk(clk_50KHz),
    .reset(sr1_reset),
    .en(sr1_en),
    .q(sr1_q)
);
/*              
  -------------------------------------------------------------------
  -- Shift Register 2  
  -- Used to count 480 us
  -------------------------------------------------------------------
*/
SR #(.REGISTER_WIDTH(7)) SR2 (
    .clk(clk_50KHz),
    .reset(sr2_reset),
    .en(sr2_en),
    .q(sr2_q)
);
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/*              
  -------------------------------------------------------------------
  -- data received logic
  -------------------------------------------------------------------
*/
reg data_RX_wr;
integer j;
initial begin
    data_RX <= 0;
end

always @ (posedge clk_1MHz or posedge reset) begin
    if (reset) begin
        data_RX <= 0;
    end
    else begin
        if (PRESENT_STATE == RX_BIT_M) begin
            if (data_RX_wr) begin
                data_RX[0] = from_dq;
                data_RX[7:1] = 0;
            end
            else begin
                data_RX[0] = data_RX[0];
                data_RX[7:1] = 0;
            end
        end
        else if (PRESENT_STATE == RX_BYTE_M) begin
            if (data_RX_wr) begin
                for (j = 0; j < 8; j = j+1) begin
                    if (sr1_q[j]) begin
                        data_RX[j] = from_dq;
                    end
                    else begin
                        data_RX[j] = data_RX[j];
                    end
                end
            end
            else begin
                data_RX = data_RX;
            end
        end
        else begin
            data_RX = 0;
        end
    end
end

integer i;
/*
  ------------------------------------------------------------------------
   -- State Mux 
   -- Combinational Logic for the state machine.
   --
   -- Any action in this state mux is synchronized with the 20 us clock
   -- and a few of them are synchronized with the 1us clock.
   --
   -- The transition of the state will take effect on next
   -- rising edge of the clock. 
   ------------------------------------------------------------------------
*/ 
always @ (*) begin
    case (PRESENT_STATE)
        /*
                                    ---------------------------------------
                                    -- DONE state
                                    ---------------------------------------
                                    -- Master wait for PS to clear GO and 
                                    -- moved to IDLE
                                    ---------------------------------------
        */
        DONE_M:begin
            read_write_dq   = 1'b1;
            to_dq           = 1'b1;
            jc1_reset       = 1'b1;     // Reset clock counters
            jc2_reset       = 1'b1;
            sr1_reset       = 1'b1;
            sr1_en          = 1'b0;
            sr2_reset       = 1'b1;
            sr2_en          = 1'b0;
            reg_wr          = 1'b0;
            done = 1'b1;
            ready           = 1'b0;
            failure = 1'b0;
            data_RX_wr = 1'b0;
            data_out = 0;
            // If PS has not cleared go, stay here to let PS fetch data
            if (go) begin
                NEXT_STATE = DONE_M;
            end
            else begin
                NEXT_STATE = IDLE_M;
            end
        end
        /*
                                    ---------------------------------------
                                    -- IDLE state
                                    ---------------------------------------
                                    -- Master waiting for go Command to
                                    -- execute next instruction.
                                    ---------------------------------------
        */
        IDLE_M:begin
            read_write_dq   = 1'b1;
            to_dq           = 1'b1;
            jc1_reset       = 1'b1;     // Reset clock counters
            jc2_reset       = 1'b1;
            sr1_reset       = 1'b1;
            sr1_en          = 1'b0;
            sr2_reset       = 1'b1;
            sr2_en          = 1'b0;
            done            = 1'b0;
            failure = 1'b0;
            ready           = 1'b1;
            reg_wr          = 1'b0;
            data_RX_wr = 1'b0;
            data_out = 0;
            // If PS issue reset, clear the done signal and stay in IDLE
            if (ctrl_reset) begin
                NEXT_STATE = IDLE_M;
                reg_wr  = 1'b1;
            end
            else begin
                // Check if go signal is issued by PS
                if (go) begin
                    NEXT_STATE  = command;  // Move to next state
                    ready       = 1'b0;
                    done        = 1'b0;
                    reg_wr      = 1'b1;
                end
                else begin
                    NEXT_STATE = IDLE_M;
                    reg_wr     = 1'b1;
                    ready           = 1'b1;
                end
            end
        end
        /*
                                    ---------------------------------------
                                    -- Reset/Initialization state
                                    ---------------------------------------
                                    -- The one-wire bus will be pulled up,
                                    -- so that next state we can send a
                                    -- Reset Pulse (active low) to the bus.
                                    ---------------------------------------
        */
        INIT_M:begin
            read_write_dq   = 1'b0;     // drive the one-wire bus high
            to_dq           = 1'b1;
            jc1_reset       = 1'b1;     // Reset clock counters
            jc2_reset       = 1'b1;
            sr1_en          = 1'b0;
            sr1_reset       = 1'b1;
            sr2_reset       = 1'b1;
            sr2_en          = 1'b0;
            reg_wr          = 1'b0;
            failure = 1'b0;
            ready           = 1'b0;
            done = 1'b0;
            data_RX_wr = 1'b0;
            data_out = 0;

            NEXT_STATE      = TX_RST_PLS;
        end
        /*
                                        ---------------------------------------
                                    -- Transmit Reset Pulse state     
                                    ---------------------------------------
                                    -- In this state, the one-wire bus will
                                    -- be pulled down (Tx "Reset Pulse") for
                                    -- 480 us to reset the one-wire
                                    -- device connected to the bus.
                                    --
                                    -- It enables FSM to move to next state
                                    -- at 480 us. The transition of the state
                                    -- will happend at 500 us.
                                    --
                                    -- Use JC1 and SR2 here to count for
                                    -- longer time duration (0 ~ 480 us):
                                    -----------------------------------------
        */
        TX_RST_PLS:begin
            
            jc2_reset   = 1'b0;
            sr2_reset   = 1'b0;
            sr2_en      = ts_60_to_80us;    // enable sr2 to count every 80us
            sr1_en          = 1'b0;
            sr1_reset       = 1'b1;
            reg_wr      = 1'b0;
            data_RX_wr = 1'b0;
            done = 1'b0;
            failure = 1'b0;
            ready           = 1'b0;
            data_out = 0;

            if (sr2_q[6]) begin             // 480 us has passed.
                read_write_dq   = 1'b1;
                to_dq           = 1'b1;
                jc1_reset       = 1'b1;     // reset the 20 us counter

                NEXT_STATE = RX_PRE_PLS; 
            end
            else begin                      // 0 ~ 480 us
                read_write_dq   = 1'b0;     // write the one-wire bus with "0"
                to_dq           = 1'b0;     // for 480 us (one-wire RESET)
                jc1_reset   = 1'b0;
                NEXT_STATE      = TX_RST_PLS;
            end
        end
        /*
                                    ---------------------------------------
                                    -- Detect Presence Pulse state     
                                    ---------------------------------------
                                    -- In this state, data on the one-wire
                                    -- bus is sampled for the presence of a slave.
                                    -- The data will be latched at 0~80 us.
                                    -- Then it waits till total 500us has
                                    -- has passed, and moves to next state
                                    -- or goes back to INIT state according 
                                    -- to the presence of the "Presence
                                    -- Pulse"
                                    --
                                    -- Use JC1 and SR2 here to count for
                                    -- longer time duration (0 ~ 480 us)
                                    ----------------------------------------
        */
        RX_PRE_PLS:begin
            jc1_reset       = 1'b0;
            jc2_reset       = 1'b0;
            sr2_reset       = 1'b0;             // use sr2 to create a 480 us counter
            sr2_en          = ts_60_to_80us;    // enable sr2 to count every 80us
            sr1_en          = 1'b0;
            sr1_reset       = 1'b1;
            reg_wr          = 1'b0;
            data_RX_wr = 1'b0;
            ready           = 1'b0;
            
            read_write_dq   = 1'b1;
            to_dq           = 1'b0;
            data_out = 0;

            if (sr2_q[5]) begin                                 // wait for 480us to pass
                reg_wr  = 1'b1;
                if (from_dq_pp == 1'b0 & from_dq == 1'b1) begin // slave is present and pull-up is present
                    done        = 1'b1;
                    failure     = 1'b0;
                    NEXT_STATE  = DONE_M;  // Move to next state
                end
                else begin                                      // no slave present try again
                    failure     = 1'b1;
                    done        = 1'b1;
                    NEXT_STATE = DONE_M;
                end
            end
            else begin                                          // 0 ~ 480 us
                NEXT_STATE = RX_PRE_PLS;
                done = 1'b0;
                failure = 1'b0;
                reg_wr          = 1'b0;
            end
        end
        /*
                                    ---------------------------------------
                                    -- Receive Bit from Device
                                    ---------------------------------------
                                    -- In this state, the onewire bus is
                                    -- pulled down during first 1 us, this
                                    -- is the initialization of the Rx of one
                                    -- bit . Then it release the bus by changing
                                    -- back to read mode.
                                    --
                                    -- From 13us to 15 us, it samples the 
                                    -- data on the one-wire bus, and assert
                                    -- databit_valid signal. 
                                    --
                                    -- After 15us, it releases the bus allowing
                                    -- the one-wire bus to be pulled back to
                                    -- high.
                                    --
                                    -- After 80us, one bit has been read.
                                    -----------------------------------------
        */
        RX_BIT_M:begin
            jc1_reset       = 1'b0;
            jc2_reset       = 1'b0;
            sr1_en          = 1'b0;
            sr1_reset       = 1'b1;
            sr2_en          = 1'b0;
            sr2_reset       = 1'b1;
            ready           = 1'b0;
            read_write_dq   = 1'b1;
            reg_wr          = 1'b0;
            failure = 1'b0;

            if (ts_0_to_1us) begin      // pull down one_wire bus
                read_write_dq   = 1'b0;
                to_dq           = 1'b0;
                NEXT_STATE      = RX_BIT_M;
                data_RX_wr = 1'b0;
                done = 1'b0;
                data_out = 0;
            end

            else if (ts_60_to_80us) begin
                read_write_dq   = 1'b1;
                to_dq           = 1'b1;
                done            = 1'b1;
                reg_wr          = 1'b1;
                data_out        = data_RX;
                data_RX_wr = 1'b0;

                // bit has been received
                NEXT_STATE      = DONE_M;
            end

            else begin                      // 1-60us
                read_write_dq   = 1'b1;     // release the bus
                to_dq           = 1'b1;
                done = 1'b0;
                data_out = 0;
                if (ts_14_to_15us) begin    // Read time slot
                    data_RX_wr = 1'b1;  // bit from 1-wire stored to data_RX lsb
                end
                else begin
                    data_RX_wr = 1'b0;
                end

                NEXT_STATE      = RX_BIT_M;
            end
        end
        /*
                                    ---------------------------------------
                                    -- Receive Byte from Device
                                    ---------------------------------------
                                    -- In this state, the onewire bus is
                                    -- pulled down during first 1 us, this
                                    -- is the initialization of the Rx of one
                                    -- bit . Then it release the bus by changing
                                    -- back to read mode.
                                    --
                                    -- From 13us to 15 us, it samples the 
                                    -- data on the one-wire bus, and assert
                                    -- databit_valid signal. 
                                    --
                                    -- After 15us, it releases the bus allowing
                                    -- the one-wire bus to be pulled back to
                                    -- high.
                                    --
                                    -- At 60us, it enables SR1 to shift to
                                    -- next bit. After 80us, one bit has
                                    -- been read. Then it repeats
                                    -- the process to receive other 7
                                    -- bits in one byte.
                                    -----------------------------------------
        */
        RX_BYTE_M:begin
            jc1_reset       = 1'b0;
            jc2_reset       = 1'b0;
            sr1_en          = 1'b0;
            sr1_reset       = 1'b0; // start to use sr1 to count 8 bits.
            sr2_en          = 1'b0;
            sr2_reset       = 1'b1;
            ready           = 1'b0;
            read_write_dq   = 1'b1;
            reg_wr          = 1'b0;
            failure = 1'b0;

            if (ts_0_to_1us) begin      // pull down one_wire bus
                read_write_dq   = 1'b0;
                to_dq           = 1'b0;
                sr1_en          = 1'b0;
                NEXT_STATE      = RX_BYTE_M;
                data_RX_wr = 1'b0;
                done = 1'b0;
                data_out = 0;
            end

            else if (ts_60_to_80us) begin
                read_write_dq   = 1'b1;
                to_dq           = 1'b1;
                sr1_en          = 1'b1;
                data_RX_wr = 1'b0;

                if (sr1_q[7]) begin
                    data_out        = data_RX;
                    done            = 1'b1;
                    reg_wr          = 1'b1;
                    
                    // byte has been received
                    NEXT_STATE = DONE_M;  // Move to next state
                end
                else begin
                    NEXT_STATE = RX_BYTE_M;
                    done = 1'b0;
                    data_out = 0;
                end
            end

            else begin                              // 1-60us
                read_write_dq   = 1'b1;     // release the bus
                to_dq           = 1'b1;
                sr1_en          = 1'b0;
                done = 1'b0;
                data_out = 0;
                if (ts_14_to_15us) begin    // Read time slot
                    data_RX_wr = 1'b1;
                end
                else begin
                    data_RX_wr = 1'b0;
                end
                NEXT_STATE = RX_BYTE_M;       // continue to assemble the data bytes
            end
        end
        /*
                                    ---------------------------------------
                                    -- Transmit Bit to device
                                    ---------------------------------------
                                    -- In this state, the one-wire bus is
                                    -- pulled down during first 10 us.
                                    --
                                    -- Then according to each bit of data
                                    -- in the tx_data register, we write data 
                                    -- to Device
                                    -- Device:
                                    -- (1) if we need to write '1' to the serial
                                    -- number device, it will release
                                    -- the one-wire bus to allow the
                                    -- pull-up resistor to pull the wire to '1'.
                                    -- (2) if we need to write '0' to
                                    -- the device, we output '0' directly
                                    -- to the bus. This process happens from
                                    -- 10 us to 60 us.
                                    -- 
                                    -- After 60us, it releases the bus allowing
                                    -- the one-wire bus to be pulled back to
                                    -- high, and enable SR1 to shift to 
                                    -- next bit.
                                    -----------------------------------------
        */
        TX_BIT_M:begin
            jc1_reset       = 1'b0;
            jc2_reset       = 1'b0;
            sr1_en          = 1'b0;
            sr1_reset       = 1'b1;
            sr2_en          = 1'b0;
            sr2_reset       = 1'b1;
            reg_wr          = 1'b0;
            data_RX_wr = 1'b0;
            failure = 1'b0;
            ready           = 1'b0;
            data_out = 0;
            if (ts_0_to_10us) begin         // pull down one_wire bus
                read_write_dq   = 1'b0;
                to_dq           = 1'b0;
                done = 1'b0;
                reg_wr          = 1'b0;
                NEXT_STATE      = TX_BIT_M;
            end

            else if (ts_60_to_80us) begin   // release the bus
                read_write_dq   = 1'b1;
                to_dq           = 1'b1;
                done            = 1'b1;
                reg_wr          = 1'b1;
                NEXT_STATE      = DONE_M;  // Move to next state
            end

            else begin  // write the command bit from 10 us to 60 us
                read_write_dq   = tx_data[0];
                to_dq           = tx_data[0];
                done = 1'b0;
                reg_wr          = 1'b0;
                NEXT_STATE  = TX_BIT_M;
            end
        end
        /*
                                    ---------------------------------------
                                    -- Transmit Byte to device
                                    ---------------------------------------
                                    -- In this state, the one-wire bus is
                                    -- pulled down during first 10 us.
                                    --
                                    -- Then according to each bit of data
                                    -- in the tx_data register, we write data 
                                    -- to Device
                                    -- Device:
                                    -- (1) if we need to write '1' to the serial
                                    -- number device, it will release
                                    -- the one-wire bus to allow the
                                    -- pull-up resistor to pull the wire to '1'.
                                    -- (2) if we need to write '0' to
                                    -- the device, we output '0' directly
                                    -- to the bus. This process happens from
                                    -- 10 us to 60 us.
                                    -- 
                                    -- After 60us, it releases the bus allowing
                                    -- the one-wire bus to be pulled back to
                                    -- high, and enable SR1 to shift to 
                                    -- next bit.
                                    --  
                                    -- After another 20us, the transition of SR1
                                    -- will take place. The process will repeat
                                    -- to transmit another bit in the MEM Command,
                                    -- till all 8 bits in the MEM Command have
                                    -- been sent out. 
                                    -----------------------------------------
        */
        TX_BYTE_M:begin
            jc1_reset       = 1'b0;
            jc2_reset       = 1'b0;
            sr1_reset       = 1'b0; // use sr1 to count the 8 bits
            sr1_en          = 1'b0;
            sr2_en          = 1'b0;
            sr2_reset       = 1'b1;
            reg_wr          = 1'b0;
            data_RX_wr = 1'b0;
            failure = 1'b0;
            ready           = 1'b0;
            data_out = 0;
            if (ts_0_to_10us) begin         // pull down one_wire bus
                read_write_dq   = 1'b0;
                to_dq           = 1'b0;
                sr1_en          = 1'b0;
                done = 1'b0;
                NEXT_STATE      = TX_BYTE_M;
                reg_wr          = 1'b0;
            end

            else if (ts_60_to_80us) begin   // release the bus
                read_write_dq   = 1'b1;
                to_dq           = 1'b1;
                sr1_en          = 1'b1;
                if (sr1_q[7]) begin
                    done        = 1'b1;
                    reg_wr      = 1'b1;
                    // Byte has sent
                    NEXT_STATE  = DONE_M;  // Move to next state
                end
                else begin
                    NEXT_STATE = TX_BYTE_M;
                    done = 1'b0;
                    reg_wr          = 1'b0;
                end
            end

            else begin  // write the command bit from 10 us to 60 us
                read_write_dq = 1'b1;
                to_dq = 1'b1;
                for (i = 0; i < 8; i = i+1) begin
                    if (sr1_q[i]) begin
                        read_write_dq   = tx_data[i];
                        to_dq           = tx_data[i];
                    end
                end
                sr1_en      = 1'b0;
                reg_wr          = 1'b0;
                NEXT_STATE  = TX_BYTE_M;
                done = 1'b0;
            end
        end
        default:begin
            NEXT_STATE = IDLE_M;
            data_RX_wr = 1'b0;
            done = 1'b0;
            failure = 1'b0;
            jc1_reset   = 1'b0;
            jc2_reset = 1'b0;
            read_write_dq   = 1'b1;
            ready           = 1'b0;
            reg_wr          = 1'b0;
            sr1_en          = 1'b0;
            sr1_reset       = 1'b1;
            sr2_en          = 1'b0;
            sr2_reset       = 1'b1;
            to_dq           = 1'b1;
            data_out = 0;
        end
    endcase
end

endmodule