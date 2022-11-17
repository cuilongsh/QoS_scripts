#!/bin/bash
i=1
id=$(date +%N)
while [ true ]
do
  rm -f destination.flv
  start=$(date +%s)
  ffmpeg -i /root/mp4/test_1080p.mp4 -c:v libx264 -crf 30 -threads 8 destination.flv
  end=$(date +%s)
  echo "Time used($id - $i): $(($end - $start))" >> /root/mp4/rtime.txt
  i=$(($i + 1))
done
