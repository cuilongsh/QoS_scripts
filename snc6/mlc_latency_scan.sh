#L1d cache:             48K
#L1i cache:             32K
#L2 cache:              1280K
#L3 cache:              49152K
#NUMA node0 CPU(s):     0-31,64-95
#NUMA node1 CPU(s):     32-63,96-127

echo "disable C2,C6"
ret=`cpupower idle-set -d 2`
ret=`cpupower idle-set -d 3`

echo "Set max, min to 2.0Ghz"
ret=`cpupower frequency-set -u 2000Mhz`
ret=`cpupower frequency-set -d 2000Mhz`


for size in {1,4,8,16,32,48,64,128,256,512,960,1024,1280,1560,2048,4096,8192,12288,16384,20480,24576,32768,49152,73728,98304,196608,393216} ; do

#mlc_3.9 --loaded_latency -R -d0 -t5 -b${size}k -k2  

mlc --loaded_latency -R -d0 -t5 -b${size}k -k2  

done 
