
#for core_count in {48,32,16,8,4,2}; do

##by HT scaling start
##echo 0-0
##mlc --loaded_latency -b1000M -R -t20 -T -k0 -d0| grep 00000 | awk '{print $3}'

for core_count in $(seq 2 2 96);do

start_1st_half=0
start_2nd_half=96

end_1st_half=$(($core_count/2 -1))
end_2nd_half=$(($end_1st_half + $start_2nd_half))
echo $start_1st_half - $end_1st_half,$start_2nd_half - $end_2nd_half

#HT by HT scaling
#with both sibling cores
##mlc --loaded_latency -b1000M -R -t20 -T -k$start_1st_half-$end_1st_half,$start_2nd_half-$end_2nd_half -d0| grep 00000 | awk '{print $3}'
##echo $start_1st_half - $(($end_1st_half+1)),$start_2nd_half - $end_2nd_half
#add one more hyper thread 
##mlc --loaded_latency -b1000M -R -t20 -T -k$start_1st_half-$(($end_1st_half+1)),$start_2nd_half-$end_2nd_half -d0| grep 00000 | awk '{print $3}'


##with physical core only
mlc --loaded_latency -b1000M -R -t20 -T -k$start_1st_half-$end_1st_half -d0| grep 00000 | awk '{print $3}' 

done
