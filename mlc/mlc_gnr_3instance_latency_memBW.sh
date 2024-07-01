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

##SNC3,phy core only
SNC0_CORES="0-39"
SNC1_CORES="40-79"
SNC2_CORES="80-119"

MLC_SNC0_CORES=0-38
SNC0_LATENCY_CORE=39

MLC_SNC1_CORES=40-78
SNC1_LATENCY_CORE=79

MLC_SNC2_CORES=80-118
SNC2_LATENCY_CORE=119

#enable prefetch on all core
# for i in {0..191}; do wrmsr -p $i 0x1a4 0xf; done
wrmsr --all 0x1a4 0x100

# disable the prefetch for latency measurement core
wrmsr -p $SNC0_LATENCY_CORE 0x1a4 0xef
wrmsr -p $SNC1_LATENCY_CORE 0x1a4 0xef
wrmsr -p $SNC2_LATENCY_CORE 0x1a4 0xef
# disable the prefetch for sibling core
wrmsr -p 279 0x1a4 0xef
wrmsr -p 319 0x1a4 0xef
wrmsr -p 359 0x1a4 0xef


#echo off > /sys/devices/system/cpu/smt/control

i=2
                        wait_mlc_exit
                        echo "test started W$i" >>3_instance_mlc.log
			mlc -c$SNC0_LATENCY_CORE  -e --loaded_latency -d0 -W$i -k$MLC_SNC0_CORES -b1g -t30 -j0 | grep 00000 | awk '{print "SNC0_only =" $2,$3}'  >>3_instance_mlc.log

                        wait_mlc_exit
                        mlc -c$SNC1_LATENCY_CORE  -e --loaded_latency -d0 -W$i -k$MLC_SNC1_CORES -b1g -t30 -j1 | grep 00000 | awk '{print "SNC1_only =" $2,$3}'  >>3_instance_mlc.log

                        wait_mlc_exit
                        mlc -c$SNC2_LATENCY_CORE  -e --loaded_latency -d0 -W$i -k$MLC_SNC2_CORES -b1g -t30 -j2 | grep 00000 | awk '{print "SNC2_only =" $2,$3}'  >>3_instance_mlc.log

			wait_mlc_exit
                        time mlc -c$SNC0_LATENCY_CORE -e --loaded_latency -d0 -W$i -k$MLC_SNC0_CORES -b1g -t30 -j0 | grep 00000 | awk '{print "SNC0_mix  =" $2,$3}'  >>3_instance_mlc.log &

                        time mlc -c$SNC1_LATENCY_CORE -e --loaded_latency -d0 -W$i -k$MLC_SNC1_CORES -b1g -t30 -j1 | grep 00000 | awk '{print "SNC1_mix  =" $2,$3}'  >>3_instance_mlc.log &
                        
                        time mlc -c$SNC2_LATENCY_CORE -e --loaded_latency -d0 -W$i -k$MLC_SNC2_CORES -b1g -t30 -j2 | grep 00000 | awk '{print "SNC2_mix  =" $2,$3}'  >>3_instance_mlc.log &

                        wait_mlc_exit

#restore the settings,reenable prefetch on all core
# for i in {0..191}; do wrmsr -p $i 0x1a4 0x2; done
wrmsr --all 0x1a4 0x100
