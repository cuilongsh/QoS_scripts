# shellcheck shell=ksh

g_ret_data=0

wait_mlc_exit() {
        while [[ -n $(pidof mlc) ]]; do
                sleep 2
        done
}


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


if [ -e /sys/fs/resctrl/guaranteed ]
then
echo "resctrl already mounted and inited"
else
mount resctrl -t resctrl /sys/fs/resctrl/ 
mkdir /sys/fs/resctrl/guaranteed
mkdir /sys/fs/resctrl/mid
mkdir /sys/fs/resctrl/besteffort
fi

##SNC4,phy core only
LP_CORES="24-35,120-131"
HP_CORES="36-47,132-143"

MLC_LP_CORES=24-34,120-130
LP_LATENCY_CORE=35

MLC_HP_CORES=36-46,132-142
HP_LATENCY_CORE=47

#echo "$HP_CORES" >/sys/fs/resctrl/guaranteed/cpus_list
#echo "$LP_CORES" >/sys/fs/resctrl/besteffort/cpus_list


#enable prefetch
# for i in {0..191}; do wrmsr -p $i 0x1a4 0xf; done
wrmsr --all 0x1a4 0x0

wrmsr -p $LP_LATENCY_CORE 0x1a4 0x2f
wrmsr -p $HP_LATENCY_CORE 0x1a4 0x2f

#echo off > /sys/devices/system/cpu/smt/control

i=2
                        # else body
                        # lp 46cores(15cores, 46hyper thread)
                        wait_mlc_exit
                        #echo $$ >/sys/fs/resctrl/besteffort/tasks
                        echo "setponit $input_setponit W $i" >>lp_only.log
                        mlc -c$LP_LATENCY_CORE  -e --loaded_latency -d0 -W$i -k$MLC_LP_CORES -b1g -t30 >>lp_only.log

                        # # hp 46cores
                        #echo $$ >/sys/fs/resctrl/guaranteed/tasks
                        echo "setponit $input_setponit W $i" >>hp_only.log
                        mlc -c$HP_LATENCY_CORE  -e --loaded_latency -d0 -W$i -k$MLC_HP_CORES -b1g -t30 >>hp_only.log

                        wait_mlc_exit
                        ##echo $$ >/sys/fs/resctrl/besteffort/tasks
                        echo "setponit $input_setponit W $i" >>lp_mix.log
                        time mlc -c$LP_LATENCY_CORE -e --loaded_latency -d0 -W$i -k$MLC_LP_CORES -b1g -t30 >>lp_mix.log &
			##wait_mlc_started /sys/fs/resctrl/besteffort/tasks 67

                        ##echo $$ >/sys/fs/resctrl/guaranteed/tasks
                        echo "setponit $input_setponit W $i" >>hp_mix.log
                        time mlc -c$HP_LATENCY_CORE -e --loaded_latency -d0 -W$i -k$MLC_HP_CORES -b1g -t30 >>hp_mix.log &

                        wait_mlc_exit
                        ##echo $$ >/sys/fs/resctrl/guaranteed/tasks
                        # hp 6cores
                        ##echo "setponit $input_setponit W $i" >>hp_only_light.log
                        ##mlc -c24 -i24 -e --loaded_latency -d0 -W$i -k26-28,122-124 -b1g -t20 >>hp_only_light.log

                        ##wait_mlc_exit
                        ##echo $$ >/sys/fs/resctrl/besteffort/tasks
                        # lp 46cores
                        ##echo "setponit $input_setponit W $i" >>lp_mix_light.log
                        ##mlc -c23 -i23 -e --loaded_latency -d0 -W$i -k0-22,96-118 -b1g -t20 >>lp_mix_light.log &
                        ##echo $$ >/sys/fs/resctrl/guaranteed/tasks
                        # hp 6cores
                        ##echo "setponit $input_setponit W $i" >>hp_mix_light.log
                        ##mlc -c24 -i24 -e --loaded_latency -d0 -W$i -k26-28,122-124 -b1g -t20 >>hp_mix_light.log &


#enable prefetch
# for i in {0..191}; do wrmsr -p $i 0x1a4 0x2; done
wrmsr --all 0x1a4 0x0
