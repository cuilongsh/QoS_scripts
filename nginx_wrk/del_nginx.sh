#!/bin/bash

for i in {1..23}
do
    echo "docker stop and remove $i-nginx-web"
    docker stop $i-nginx-web;docker rm $i-nginx-web

    iptables -t nat -D DOCKER 2
done

