##by HT scaling start
patn=$1

echo 1 - 1
mlc --loaded_latency -b600M -$patn -t20 -k1 -d0| grep 00000 | awk '{print $2,$3}' >>mlc_core_scaling_$patn.txt

for core_count in $(seq 2 2 79);do

start_1st_half=1
start_2nd_half=121

end_1st_half=$(($core_count/2 -1+$start_1st_half))
end_2nd_half=$(($end_1st_half + $start_2nd_half-$start_1st_half))
echo $start_1st_half - $end_1st_half,$start_2nd_half - $end_2nd_half

#HT by HT scaling
#with both sibling cores
mlc --loaded_latency -b600M -$patn -t20 -k$start_1st_half-$end_1st_half,$start_2nd_half-$end_2nd_half -d0| grep 00000 | awk '{print $2,$3}'>>mlc_core_scaling_$patn.txt
#echo $start_1st_half - $(($end_1st_half+1)),$start_2nd_half - $end_2nd_half
#add one more hyper thread 
mlc --loaded_latency -b600M -$patn -t20 -k$start_1st_half-$(($end_1st_half+1)),$start_2nd_half-$end_2nd_half -d0| grep 00000 | awk '{print $2,$3}'>>mlc_core_scaling_$patn.txt


##with physical core only
#mlc --loaded_latency -b1000M -R -t20 -T -k$start_1st_half-$end_1st_half -d0| grep 00000 | awk '{print $3}' 

done
