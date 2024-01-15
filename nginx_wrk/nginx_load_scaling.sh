
for cpus in {0.05,0.1,0.15,0.2,0.25,0.3,0.35,0.4,0.45,0.5,0.55,0.6,0.65,0.7,0.75,0.8,0.85,0.9}
do
   for i in {1..31} 
   do docker update --cpus=$cpus $i-nginx-web
   echo $cpus-$i
   done 
sleep 1;
time numactl -C 32-56,96-120 wrk_org --timeout 2s -t 48 -c48  -d 30s http://10.239.129.81:9000/4kb.bin;
done
