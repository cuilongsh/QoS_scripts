

#SNC6
#NUMA node0 CPU(s):     0-19,120-139
#NUMA node1 CPU(s):     20-39,140-159
#NUMA node2 CPU(s):     40-60,160-180
#NUMA node3 CPU(s):     61-79,181-199
#NUMA node4 CPU(s):     80-98,200-218
#NUMA node5 CPU(s):     99-119,219-239


for core_count in $(seq 1 1 119);do

start_1st_half=40
start_2nd_half=280

end_1st_half=$(($core_count/2 -1+$start_1st_half))
end_2nd_half=$(($end_1st_half + $start_2nd_half-$start_1st_half))
#echo $start_1st_half - $end_1st_half,$start_2nd_half - $end_2nd_half
echo $core_count
#physical core
mlc --loaded_latency -b1000M -R -t20 -k1-$core_count -d0| grep 00000 | awk '{print $2,$3}' >> core_scaling.txt

#add one more hyper thread 
#mlc --loaded_latency -b1000M -R -t20 -T -k$start_1st_half-$(($end_1st_half+1)),$start_2nd_half-$end_2nd_half -d0| grep 00000 | awk '{print $3}'


##with physical core only
#mlc --loaded_latency -b1000M -R -t20 -T -k$start_1st_half-$end_1st_half -d0| grep 00000 | awk '{print $3}' 

done
