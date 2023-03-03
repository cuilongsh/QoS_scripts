#!/bin/bash
ulimit -n 65535
REDIS_CMD=$PWD/redis-server

MEMTIER_CMD=$PWD/memtier_benchmark_2ms

#SPR 48C,2S
#NUMA node0 CPU(s):   0-47,96-143
#NUMA node1 CPU(s):   48-95,144-191
#socket0
#REDIS_CORES={{24..47},{120..143}
#BWAVES_CORES=`{{0..23},{96..119}}`
#Socket1
#MEMTIER_CORES={{72-95,168-191}}

#on sibling core
#REDIS_CORES={{0..47}}
#BWAVES_CORES=`{{96..143}}`
#Socket1
#MEMTIER_CORES={{48-95}}

#SPR 32C HT on
#NUMA node0 CPU(s):   0-31,64-95
#NUMA node1 CPU(s):   32-63,96-127
#socket0
#REDIS_CORES={{16..31},{80..95}
#BWAVES_CORES=`{{0..15},{64..79}}`
#Socket1
#MEMTIER_CORES={{48-63,112-127}}

last_redis=0
last_memtier=0

start_redis-server(){

    echo "start redis server"
    for i in {0..47}
    do
      echo "running redis on core$i port@$port"
      taskset -c $i $REDIS_CMD --port ${port} > /dev/null 2>&1&
      last_redis=$!
      port=$((${port}+1))
    done

    sleep 3


    mpstat -P `echo {0..47} |sed -e 's/ /,/g'` 30 1 > logs/cpuutil/test${1}-cpu.log&

}

start_memtier_benchmark(){

    echo "start memtier client"
    for i in {48..95} 
    do
      echo "running memtier on core$i,port@$port" 
      taskset -c $i $MEMTIER_CMD -s localhost -p ${port} --pipeline=30 -c 1 -t 1 -d 1024 --key-maximum=42949 --key-pattern=G:G --key-stddev=1177 --ratio=1:1 --distinct-client-seed --random-data --test-time=60 --run-count=1 --hide-histogram &>logs/${1}/redis-core${i}.log &
      last_memtier=$!
      echo $last_memtier
      port=$((${port}+1))
    done
   
    if [ $1 == 1 ]
    then
    sleep 1
    else
    #only for response time
    sleep 10
    start_bwaves 
    fi

    wait $last_memtier
    killall redis-server 
}

start_bwaves(){
    instanceNum=24
    echo "start lp"
    #docker run --cpuset-cpus=0-15,64-79 --name speccpuBwaves --rm -e INSTANCES=$instanceNum -e WORKLOAD=bwaves spec17:0.6 > /dev/null 2>&1&
    #docker run --privileged --cpuset-cpus=0-15,64-79 --name speccpuBwaves --rm -e INSTANCES=${instanceNum} --cpuset-mems=0  -v `pwd`/test:/home/spec17/result/ -e WORKLOAD=bwaves speccpu2017:rate > /dev/null 2>&1&
    #docker is not working on CentOS8, using mlc as the agressor
    mlc --loaded_latency -d0 -R -t300 -T -k96-143 > /dev/null 2>&1&
   
    #sleep 20
}


function colocation(){
    echo "********************************************************************"
    echo "****************************start test $1****************************"
    echo "********************************************************************"

    #sleep 10
    #start_bwaves 

    port=7777
    start_redis-server $1

    port=7777
    start_memtier_benchmark $1


    ps aux |grep -E 'redis-server\ \*:|$MEMTIER_CMD \-s|starter.py\ imc_config.json'|awk '{print $2}' | while read line;
 do kill -9 $line; done
    #docker stop speccpuBwaves
    killall mlc
}

function set_mba_10(){
    echo "set LP MBA=10"
#map CLOS1 to povray
#map CLOS2 to perlbench
    #pqos -e "llc:1=0x7fff"
    #pqos -e "llc:2=0x7fff"
    pqos -e "mba:1=100"
    pqos -e "mba:2=10"
#Apply to
#HP

#SPR 48C,2S
#socket0
#REDIS_CORES={{24..47},{120..143}
#BWAVES_CORES=`{{0..23},{96..119}}`
#Socket1
#MEMTIER_CORES={{72-95,168-191}}

 
    pqos -a "core:1=0-47"
    pqos -a "core:2=96-143"
    sleep 3
}

main() {

  rm logs -rf
#Disable C6,C2:
cpupower idle-set -d 2
cpupower idle-set -d 3

#Set max, min to 2.7Ghz:
cpupower frequency-set -u 2700Mhz
cpupower frequency-set -d 2700Mhz

  pqos -R
  CORES=$1
  CORESIndex=$[$CORES-1]

  mkdir logs
  cd logs
  for i in {1..4}
  do
    mkdir $i
  done
  mkdir cpuutil
  cd ..

  #redis+memtier only
  colocation 1

  #redis+memtier(HP)  + bwaves- no rdt
  colocation 2

  #redis+memtier(HP)  + bwaves- MBA=10
  pqos -R
  set_mba_10
  colocation 3

  #redis+memtier(HP)  + bwaves- DRC ,setpoint=2
##  pqos -R
  #source ./hwdrc_init_to_default_pqos_icx_2S_xcc_d1.sh
##  source ./hwdrc_spr_2S_xcc_init_to_default_pqos.sh 
##  source ./hwdrc_reg_dump_msr.sh
##  pqos -m all:[16-31,80-95][48-63,112-127][0-15,64-79] -i 1 -o logs/pqos_mon_test.log & 
##  colocation 4

#SPR 48C,2S
#socket0
#REDIS_CORES={{24..47},{120..143}
#BWAVES_CORES=`{{0..23},{96..119}}`
#Socket1
#MEMTIER_CORES={{72-95,168-191}}
  
  #disable MEMCLOS DRC
  #RD_WR=WR
  #MEMCLOS_EN=0
##  wrmsr -p 1 0xb1 0x80000000
##  wrmsr -p 1 0xb0 0x810054d0
##  echo "MEMCLOS_EN=0"
##  rdmsr -p 1 0xb1;rdmsr -p 1 0xb0
##  sleep 1;

  sync
  killall pqos
  sync
  sed -e 's/^M/\n/g' ./logs/4/redis-core48.log |awk '{print $10,$17}' > ./logs/hwdrc_raw_48.log
  grep -r "0-15,64-" ./logs/pqos_mon_test.log|awk '{print $5,$6}' > ./logs/mbm_0-11_bwaves_LP.txt
  grep -r "16-31,80" ./logs/pqos_mon_test.log|awk '{print $5,$6}' > ./logs/mbm_12-23_redis_HP.txt
  grep -r "48-63,112" ./logs/pqos_mon_test.log|awk '{print $5,$6}' > ./logs/mbm_36-47_memtier_HP.txt
 
  pqos -R
  pqos -r -t 1
}

main "$@"
