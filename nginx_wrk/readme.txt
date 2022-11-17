1)pull nginx docker images
docker pull nginx:latest
2)start 23 instance on socket0, ecah instance take 1 core 2 hyperthreads, core 1 to 23
./start_nginx_in_docker.sh
3)start the wrk on Socket1,get the latency and request/sec 
increase the file size may get higher memory BW
# numactl -C 32-56,96-120 wrk_org --timeout 2s -t 48 -c48  -d 30s http://10.239.173.27:9000/4kb.bin  
Running 30s test @ http://10.239.173.27:9000/4kb.bin
  48 threads and 48 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    78.15us   14.06us   2.09ms   83.72%
    Req/Sec    12.60k   320.27    13.94k    71.58%
  18111956 requests in 30.10s, 71.76GB read
  Socket errors: connect 0, read 0, write 824, timeout 0
Requests/sec: 601730.95
Transfer/sec:      2.38GB
4)recover the iptables and rm nginx container
./del_nginx.sh
