

#SNC6
#NUMA node0 CPU(s):     0-19,120-139
#NUMA node1 CPU(s):     20-39,140-159
#NUMA node2 CPU(s):     40-60,160-180
#NUMA node3 CPU(s):     61-79,181-199
#NUMA node4 CPU(s):     80-98,200-218
#NUMA node5 CPU(s):     99-119,219-239

#Caches (sum of all):
#L1d:                   5.6 MiB (120 instances)--48KB for each core
#L1i:                   7.5 MiB (120 instances)--64KB for each core
#L2:                    240 MiB (120 instances)--2MB for each core
#L3:                    504 MiB (1 instance)-- 4MB for each core

#for core_count in $(seq 1 1 119);do

core_count=39

echo "start mlc in dram 1000M:"

mlc --loaded_latency -b1000M -R -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' 
#mlc --loaded_latency -b2M -R -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' 

for i in $(seq 2 1 12);
do
#physical core,1GB buffer,for DRAM 
mlc --loaded_latency -b1000M -W$i -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' 
#mlc --loaded_latency -b2M -W$i -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' 

done

echo "start mlc in LLC 2M:"
#mlc --loaded_latency -b1000M -R -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' 
mlc --loaded_latency -b2M -R -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' 

for i in $(seq 2 1 12);
do
#physical core,1GB buffer,for DRAM 
#mlc --loaded_latency -b1000M -W$i -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' 
mlc --loaded_latency -b2M -W$i -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' 

done
