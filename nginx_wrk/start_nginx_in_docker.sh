#!/bin/bash
#Disable C6,C2:
cpupower idle-set -d 2
cpupower idle-set -d 3

#Set max, min to 2.7Ghz:
cpupower frequency-set -u 2700Mhz
cpupower frequency-set -d 2700Mhz

sibling_start=96

for i in {1..32}
do
    cpu_1st=$(($i))
    #cpu_2nd=$(($cpu_1st+64))
    #cpuset="$cpu_1st,$cpu_2nd"
    cpuset=$cpu_1st
    echo "start docker $i-nginx-web cpus=$cpuset"
    docker run --privileged=true --name "$i-nginx-web" -d --cpuset-cpus=$cpuset --cpuset-mems=0 -v $PWD/nginx_web.conf:/etc/nginx/nginx.conf:ro nginx 
done


for i in {1..32}
do
    docker_ip=$(($i+1))
    #load_balence 20 ==> 1
    #load_balence=$((23-$i+1))
    load_balence=$((32-$i+1))
    docker cp 4kb.bin $i-nginx-web:/usr/share/nginx/html/
    docker cp 10kb.bin $i-nginx-web:/usr/share/nginx/html/
    docker cp 100kb.bin $i-nginx-web:/usr/share/nginx/html/
    docker cp 1mb.bin $i-nginx-web:/usr/share/nginx/html/
    docker cp 40mb.bin $i-nginx-web:/usr/share/nginx/html/
    docker cp 50mb.bin $i-nginx-web:/usr/share/nginx/html/
    docker cp 60mb.bin $i-nginx-web:/usr/share/nginx/html/
    iptables -t nat -A DOCKER ! -i docker0 -p tcp --dport 9000 -m state --state NEW -m statistic --mode nth --every $load_balence --packet 0 -j DNAT --to-destination 172.17.0.$docker_ip:80

done

