#!/bin/bash

sample_cpus_cstats(){
CPUS="/sys/devices/system/cpu/cpu[0-9]*"
##echo "Processing all cpu files in $cpuInsys..."
for cpuInsys in $CPUS
do
    CPU_number=${cpuInsys##*/}
    CSTATES="$cpuInsys/cpuidle/state[0-9]"
    ##echo "Processing all cpuilde state files in $CSTATES..."
    for cs in $CSTATES
    do echo $CPU_number `cat $cs/name` `cat $cs/time`;
    done; 
done
}

for loop in [1..24]
do
echo "TSC on core0 "`rdmsr -p0 0x10`
sample_cpus_cstats
sleep 3600;
done
