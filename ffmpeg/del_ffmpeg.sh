#!/bin/bash

for i in {0..7}
do
    echo "clear ffmpg_lp_$i"
    docker stop ffmpg_lp_$i
    docker rm ffmpg_lp_$i

done

for i in {16..23}
do
    echo "clear ffmpg_lp_$i"
    docker stop ffmpg_lp_$i
    docker rm ffmpg_lp_$i

done
