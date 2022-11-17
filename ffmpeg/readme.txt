1)download the docker image and load in to docker:
curl http://cce-docker-cargo.sh.intel.com/docker_images/ffmpeg.img.xz | xzcat - | docker load 
2)start the ffmpg on the core 0-32, 4 core for one ffmpeg instance, ffmpeg instance will be start one by one. 
the ffmpeg will be keep running.
./start_ffmpeg_in_docker.sh
3)result is in the rtimes.txt
cat mp4/rtime.txt 
4)clean the docker env, remove the running ffmpeg instance
./del_ffmpeg.sh 
