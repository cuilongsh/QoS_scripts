for i in $(seq 10 10 100) ;do cpulimit -l $i mlc --loaded_latency -R -t10 -c1 -k0 -d0 -b1000M | tail -1  ;done
