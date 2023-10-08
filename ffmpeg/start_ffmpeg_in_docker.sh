#!/bin/bash
#Disable C6,C2:
cpupower idle-set -d 2
cpupower idle-set -d 3

#Set max, min to 2.7Ghz:
#cpupower frequency-set -u 2700Mhz
#cpupower frequency-set -d 2700Mhz

socket0_HT=64
start_cpu=12


for i in {0..9}
do
    #11x 4c 16 threads FFMPEG:30S
    ##used as one of base line, max memory throughput
    cpu_1st=$(($i * 2 + 0+$start_cpu))
    cpu_2nd=$(($cpu_1st + $socket0_HT+$start_cpu))
    cpuset="$cpu_1st-$(($cpu_1st + 1)),$cpu_2nd-$(($cpu_2nd +1))"

    #11x 2c 8 threads FFMPEG,physical core only:36
    #11x 2c 6/4 threads FFMPEG,physical core only:same
    #3c 8 threads FFMPEG,physical core only:22-23@3Ghz
    #4c 9 threads, physical core only:17-18@3Ghz
    ##cpu_1st=$(($i * 4 ))
    ##cpuset="$cpu_1st-$(($cpu_1st + 3))"

    #only on sibling core
    #cpu_1st=$(($i * 4 + $socket0_HT))
    #cpuset="$cpu_1st-$(($cpu_1st + 3))"

    #7x 6c 16 threads FFMPEG:20S
    #cpu_1st=$(($i * 3 + 1))
    #cpu_2nd=$(($cpu_1st + 48))
    #cpuset="$cpu_1st-$(($cpu_1st + 2)),$cpu_2nd-$(($cpu_2nd + 2))"

    #7x 4c 16 threads FFMPEG, cover physical core,then sibling core: 18S~19s
    #cpu_1st=$(($i * 4 + 1))
    #cpu_2nd=$(($cpu_1st + 3))
    #cpuset="$cpu_1st-$(($cpu_1st +3))"

    echo $cpuset
    #1080p video
    echo "docker run -d --name ffmpg_lp_$i --cpuset-cpus=$cpuset --cpus=4 --privileged  -v $PWD/mp4:/root/mp4 --entrypoint=/root/mp4/loop_ffmpeg.sh  ffmpeg"
    #docker run -d --name ffmpg_lp_$i --cpuset-cpus=$cpuset --cpus=0.8 --privileged  -v $PWD/mp4:/root/mp4 --entrypoint=/root/mp4/loop_ffmpeg.sh  ffmpeg_eric:v1 
    docker run -d --name ffmpg_lp_$i --cpuset-cpus=$cpuset --cpus=4 --privileged  -v $PWD/mp4:/root/mp4 --entrypoint=/root/mp4/loop_ffmpeg.sh  ffmpeg_eric:v1 
    echo "pause:check the memory bandwidth"
    read myinput

done
