#!/bin/bash

lscpu


for hours in  $(seq 0 23) 
do for minutes in $(seq 1 30);
do
#echo "TSC on core0 "`rdmsr -p0 0x10`
##echo "round-"$hours":"$minutes
mpstat -P ALL 1 3
sleep 117;

done;
done
