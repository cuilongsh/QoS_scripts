#buffer_size=9000
buffer_size=$1

pqos -a "core:3=0-31"

for mba_level in $(seq 10 10 100); do
mba_string="mba:3=${mba_level}"
#echo $mba_string
pqos -e $mba_string  > /dev/null 2>&1 
sleep 1
#31C
mlc --loaded_latency -d0 -b${buffer_size}k -R -t30 -k0-30 -c31 -u |grep " 0000" |awk '{print $2,$3}';

#mlc --loaded_latency -d0 -b${buffer_size}M -R -t30 -k30 -c31 -u |grep " 0000" |awk '{print $2,$3}';

done

