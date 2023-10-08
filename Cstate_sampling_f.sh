#!/bin/bash
 
utime=`uptime`
etime=`date '+%s'`
name=`uname -rn`
model=`grep -i -m1 "model name" /proc/cpuinfo`
cores=$((`getconf _NPROCESSORS_ONLN`-1))
cstates=$((`ls -d /sys/devices/system/cpu/cpu0/cpuidle/state* | wc -l`-1))
echo -n "$name;$model;$utime;$etime;cores=$cores;visiblecstates=$cstates"
if [ "$cores" -ge 0 ] && [ "$cstates" -ge 0 ]; then
    for cpu in `seq 0 $cores`; do
        echo -n ";core=$cpu"
        for state in `seq 0 $cstates`; do
            d=/sys/devices/system/cpu/cpu${cpu}/cpuidle/state${state}
            name=`cat $d/name`
            timeinstate=`cat $d/time`
            echo -n ";$name=$timeinstate"
        done
    done
    echo ""
else
    echo ";C-state No data"
fi

