#!/bin/bash

source $PWD/hwdrc_osmailbox_config.inc.sh


hwdrc_change_setpoint(){
    echo "MEMCLOS_EN=0"
    hwdrc_write 0x810054d0 0x0

    echo "CONFIG0=" $g_CONFIG0
    hwdrc_write 0x810052d0 $g_CONFIG0

    hwdrc_write 0x810054d0 0x2 
    echo "MEMCLOS_EN=0x2"
}

#CONFIG0
#enable MEM_CLOS_EVEMT
#MEM_CLOS_EVENT= 0x80 MCLOS_RPQ_OCCUPANCY_EVENT
#MEM_CLOS_TIME_WINDOW=0x06(3ms)
#MEMCLOS_SET_POINT=0x01
input_setponit=$1
#g_CONFIG0=$(printf "0x%08x\n" $((0x01800600 + input_setponit)))
#CAS
g_CONFIG0=$(printf "0x%08x\n" $((0x01050600 + input_setponit)))

#Here the OS_MAILBOX is per_socket, so we need to pick a core from the socket you want, one core msr settings will be enough to represent the socket setup
echo "change setpoint for Scoket0"
core_id=1
hwdrc_change_setpoint $g_CONFIG0
hwdrc_reg_dump

echo "change setpoint for Scoket1"
core_id=32
hwdrc_change_setpoint $g_CONFIG0
hwdrc_reg_dump
