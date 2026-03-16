wait_mlc_started() {
#wait_mlc_started /sys/fs/resctrl/besteffort/tasks 67
#wait for $1 value==$2
        while true; do
        task_num=`cat $1 |wc -l`
        test $task_num = $2
        [ $? -eq 1 ]||break
        echo "sleep 1 seconds, wait for more mlc task, "$1 "=" $task_num
        sleep 1
        done
}


#put the shell as LP parent
##echo $$ > /sys/fs/resctrl/COS7/tasks
echo "0-9,120-129" >/sys/fs/resctrl/COS1/cpus_list
echo "10-19,130-139" >/sys/fs/resctrl/COS2/cpus_list
echo "20-29,140-149" >/sys/fs/resctrl/COS3/cpus_list
echo "30-39,150-159" >/sys/fs/resctrl/COS4/cpus_list

#one by one
mlc --loaded_latency -d0 -W3 -t20 -T -k0-9,120-129 -b300M |grep "00000" |awk '{print "COS1",$2,$3}' >>ddra_COS1.txt
mlc --loaded_latency -d0 -W3 -t20 -T -k10-19,130-139 -b300M |grep "00000" |awk '{print "COS2",$2,$3}' >>ddra_COS2.txt 
mlc --loaded_latency -d0 -W3 -t20 -T -k20-29,140-149 -b300M |grep "00000" |awk '{print "COS3",$2,$3}' >>ddra_COS3.txt
mlc --loaded_latency -d0 -W3 -t20 -T -k30-39,150-159 -b300M |grep "00000" |awk '{print "COS4",$2,$3}' >>ddra_COS4.txt

#LP (46.7GB DRAM)
mlc --loaded_latency -d0 -W3 -t20 -T -k0-9,120-129 -b300M |grep "00000" |awk '{print "COS1",$2,$3}' >>ddra_COS1.txt & 
mlc --loaded_latency -d0 -W3 -t20 -T -k10-19,130-139 -b300M |grep "00000" |awk '{print "COS2",$2,$3}' >>ddra_COS2.txt & 
mlc --loaded_latency -d0 -W3 -t20 -T -k20-29,140-149 -b300M |grep "00000" |awk '{print "COS3",$2,$3}' >>ddra_COS3.txt & 
mlc --loaded_latency -d0 -W3 -t20 -T -k30-39,150-159 -b300M |grep "00000" |awk '{print "COS4",$2,$3}' >>ddra_COS4.txt  

#wait_mlc_started /sys/fs/resctrl/COS7/tasks 247

#put the shell as LP parent
#echo $$ > /sys/fs/resctrl/COS4/tasks

#HP (19.5GB DRAM)
#mlc --loaded_latency -d0 -W3 -t50 -T -k0-19 -b500M |grep "00000" |awk '{print "HP",$2,$3}'>>ecs_HP.txt


#wait $lp_process_id
