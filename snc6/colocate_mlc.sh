function invalind_params()
{
echo "./colocate_mlc.sh on [S0|S1] [core_list_for_HP]"
echo "S0/S1:2 MLC colovated on Socket0 or Socket1"
echo "core_list_for_HP:core list for High priority TASK.Low priority work load on 32 cores"
echo "Samples:"
echo "1)run 2 MLC workloads on S0 with 2 MEM CLOS:"
echo "./workload.sh S0"
echo "2)run 2 MLC workload on S1, specify the core 32-47 to HP workload"
echo "./workload.sh S1 32-47"

exit 1
}


if [ $# -eq 0 ]; then

invalind_params

elif [ $# -eq 1 ]; then
  if [ $1 == "S0" ];then
  echo "workload on Socket 0"

start_1st_half=0
start_2nd_half=96
  elif [ $1 == "S1" ];then
  echo "workload on Socket 1"
 
start_1st_half=48
start_2nd_half=144

  else
  invalind_params
  fi
fi


for core_count in $(seq 2 2 96);do


end_1st_half=$(($core_count/2 -1+$start_1st_half))
end_2nd_half=$(($end_1st_half + $start_2nd_half- $start_1st_half))
echo $start_1st_half - $end_1st_half,$start_2nd_half - $end_2nd_half



##with physical core only
mlc --loaded_latency -b1000M -R -t20 -T -k$start_2nd_half-$end_2nd_half -d0| grep 00000 | awk '{print "LP=" $3}' & 
lp_process_id=$!

mlc --loaded_latency -b1000M -R -t20 -T -k$start_1st_half-$end_1st_half -d0| grep 00000 | awk '{print "HP=" $3}' 
#wait for lp process finished
#other wise, it may impact the next mlc workload calc
wait $lp_process_id


done
