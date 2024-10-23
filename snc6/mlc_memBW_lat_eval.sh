

#HP_CORES=$1
#LP_CORES=48-63,112-127

#XCC D0 QWAE:32C 300W, 2.9Ghz,2S HT on.
#NUMA node0 CPU(s):   0-31,64-95
#NUMA node1 CPU(s):   32-63,96-127
#HP_CORES=0-15,64-79,32-47,96-111
#LP_CORES=16-31,80-95,48-63,112-127

#XCC D1 QWMA, Ali customized SKU:24C, 185W, 2.5Ghz,2S HT on
#NUMA node0 CPU(s):     0-23,48-71
#NUMA node1 CPU(s):     24-47,72-95
#HP_CORES=0-11,48-59,24-35,72-83
#LP_CORES=12-23,60-71,36-47,84-95


function invalind_params()
{
echo "./workload.sh on [S0|S1] [core_list_for_HP]"
echo "S0/S1:workload on Socket0 or Socket1"
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
  #D0
  #HP_CORES=0-15,64-79
  #LP_CORES=16-31,80-95

  #D1
  HP_CORES=0-11,48-59
  LP_CORES=12-23,60-71

  elif [ $1 == "S1" ];then 
  echo "workload on Socket 1"
  #D0
  #HP_CORES=32-47,96-111
  #LP_CORES=48-63,112-127
  #D1
  HP_CORES=24-35,72-83
  LP_CORES=36-47,84-95

  else
  invalind_params
  fi
elif [ $# -eq 2 ]; then
  if [ $1 == "S0" ];then
  echo "workload on Socket 0"
  HP_CORES=$2
  #D0
  #LP_CORES=16-31,80-95
  #D1
  LP_CORES=12-23,60-71
  elif [ $1 == "S1" ];then
  echo "workload on Socket 1"
  HP_CORES=$2
  #D0
  #LP_CORES=48-63,112-127
  #D1
  LP_CORES=36-47,84-95
  else
  invalind_params
  fi
else
invalind_params
fi


TIME=10

function mlc_cores()
{
        cores=$1
        tag=$2
        #score=$(mlc --loaded_latency -d0 -R -t${TIME} -T -k${cores} | grep 00000 | awk '{print $3}')

        #score=$(mlc --loaded_latency -d0 -W10 -t${TIME} -T -k${cores} | grep 00000 | awk '{print $3,$2}')
        ##random acess  
        #score=$(mlc --loaded_latency -d0 -R -r -D4096 -U -T -t${TIME} -k${cores} | grep 00000 | awk '{print $3,$2}')
        if [ $tag == "lp" ];then 
        score=$(mlc --loaded_latency -d0 -R -T -t${TIME} -k${cores} | grep 00000 | awk '{print $3,$2}')
        elif  [ $tag == "hp" ];then
        score=$(mlc --loaded_latency -d0 -R -t${TIME} -k${cores} | grep 00000 | awk '{print $3,$2}')
        fi
        echo ============${tag} ${cores} = ${score}===============
}

function col()
{
HP_CORES=$1
LP_CORES=$2

echo "HP:"$HP_CORES
echo "LP:"$LP_CORES

        mlc_cores $LP_CORES lp &
        lp_process_id=$!
        mlc_cores $HP_CORES hp
        ##sleep 2
        #wait for lp process finished
        #other wise, it may impact the next mlc workload calc
        wait $!
}

function single_instance()
{
CORES=$1
echo "cores:"$CORES
        mlc_cores $CORES hp
}


cores_per_socket=0
numa_node0_1st_core=0
numa_node1_1st_core=0
numa_node0_1st_core_2nd_group=0
numa_node1_1st_core_2nd_group=0

function cpu_topo_scan()
{

cores_per_socket=`lscpu |grep "Core(s) per socket"|awk '{print $ 4}'`
echo $cores_per_socket


numa_node0_1st_core=`lscpu |grep "NUMA node0 CPU(s)"|awk -F'[- ,]'  '{print $8}'`
numa_node1_1st_core=`lscpu |grep "NUMA node1 CPU(s)"|awk -F'[- ,]'  '{print $8}'`

#leave the 1st core for latency meansurement
workload_node0_1st_core=$(($numa_node0_1st_core + 1))
workload_node1_1st_core=$(($numa_node1_1st_core + 1))

numa_node0_1st_core_group2=`lscpu |grep "NUMA node0 CPU(s)"|awk -F'[- ,]'  '{print $10}'`
numa_node1_1st_core_group2=`lscpu |grep "NUMA node1 CPU(s)"|awk -F'[- ,]'  '{print $10}'`

#leave the 1st core for latency meansurement
workload_node0_1st_core_group2=$(($numa_node0_1st_core_group2 + 1))
workload_node0_1st_core_group2=$(($numa_node1_1st_core_group2 + 1))

echo "NUMA node0" $numa_node0_1st_core "-" $numa_node0_1st_core_group2
echo "NuMA node1" $numa_node1_1st_core "-" $numa_node1_1st_core_group2

}

function mlc_col_scan_cores_in_numa_node0_pysical_core
{

testloops=$(($1-1))
numa_node0_1st_core=$(($numa_node0_1st_core +1))
lp_start1=$(($cores_per_socket / 2 +1))

for i in `seq 0 $testloops`;
do
end_group1=$(($numa_node0_1st_core + $i ))
lp_end_group1=$(($lp_start1 + $i ))

col $numa_node0_1st_core"-"$end_group1 $lp_start1"-"$lp_end_group1
done
}


function mlc_scan_cores_in_numa_node0_pysical_core
{

testloops=$(($1-1))
numa_node0_1st_core=$(($numa_node0_1st_core +1))

for i in `seq 0 $testloops`;
do
end_group1=$(($numa_node0_1st_core + $i ))

single_instance $numa_node0_1st_core"-"$end_group1
done
}

function mlc_col_scan_cores_in_numa_node0_ht_core
{

testloops=$1
#numa_node0_1st_core=$(($numa_node0_1st_core +1))
lp_start1=$(($cores_per_socket / 2 ))
lp_start2=$(($numa_node0_1st_core_group2+$lp_start1))


for i in `seq 0 $testloops`;
do
end_group1=$(($numa_node0_1st_core + $i ))
lp_end_group1=$(($lp_start1 + $i ))
lp_end_group2=$((lp_start2 +$i))

end_group2=$(($numa_node0_1st_core_group2 + $i ))


col $numa_node0_1st_core"-"$end_group1","$numa_node0_1st_core_group2"-"$end_group2 $lp_start1"-"$lp_end_group1","$lp_start2"-"$lp_end_group2
done
}

function mlc_single_scan_cores_in_numa_node0_ht_core
{

testloops=$1

for i in `seq 0 $testloops`;
do
end_group1=$(($numa_node0_1st_core + $i ))

end_group2=$(($numa_node0_1st_core_group2 + $i ))

single_instance $numa_node0_1st_core"-"$end_group1","$numa_node0_1st_core_group2"-"$end_group2
done
}


function mlc_single_scan_cores_in_numa_node0_ht_core_no_core0
{

testloops=$(($1-1))
numa_node0_1st_core=$(($numa_node0_1st_core +1))
numa_node0_1st_core_group2=$(($numa_node0_1st_core_group2+1))

for i in `seq 0 $testloops`;
do
end_group1=$(($numa_node0_1st_core + $i ))
end_group2=$(($numa_node0_1st_core_group2 + $i ))

single_instance $numa_node0_1st_core"-"$end_group1","$numa_node0_1st_core_group2"-"$end_group2
done
}

function mlc_col_scan_cores_in_numa_node0_ht_core_no_core0
{

testloops=$(($1-1))
numa_node0_1st_core=$(($numa_node0_1st_core +1))
numa_node0_1st_core_group2=$(($numa_node0_1st_core_group2+1))
lp_start1=$(($cores_per_socket / 2 +1))
lp_start2=$(($numa_node0_1st_core_group2+$lp_start1-1))


for i in `seq 0 $testloops`;
do
end_group1=$(($numa_node0_1st_core + $i ))
lp_end_group1=$(($lp_start1 + $i ))
lp_end_group2=$((lp_start2 +$i))

end_group2=$(($numa_node0_1st_core_group2 + $i ))


col $numa_node0_1st_core"-"$end_group1","$numa_node0_1st_core_group2"-"$end_group2 $lp_start1"-"$lp_end_group1","$lp_start2"-"$lp_end_group2
done
}
cpu_topo_scan

half_cores=`expr $cores_per_socket / 2 - 1`
echo $half_cores
all_cores=`expr $cores_per_socket - 1`


##mlc_col_scan_cores_in_numa_node0_pysical_core $half_cores


##mlc_scan_cores_in_numa_node0_pysical_core $all_cores
mlc_single_scan_cores_in_numa_node0_ht_core_no_core0 $all_cores

#with core0
#mlc_col_scan_cores_in_numa_node0_ht_core $half_cores

##mlc_col_scan_cores_in_numa_node0_ht_core_no_core0 $half_cores
