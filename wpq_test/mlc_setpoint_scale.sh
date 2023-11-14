# shellcheck shell=ksh
source $PWD/hwdrc_osmailbox_config.inc.sh

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

#enable hwdrc
# hwdrc_enable

#Map CLOS0-3,8-15 and CLOS4 to MCLOS 0(HP) ,CLOS 5-MCLOS 1, CLOS6- MCLOS 2, CLOS7-MCLOS3(LP)
#resctrl_config init
#48C
#LP_CORES=0-23,96-119   #32-47,96-110
#HP_CORES=24-47,120-143 #48-63,112-126

#32C
#NUMA node0 CPU(s):   0-31,64-95
#NUMA node1 CPU(s):   32-63,96-127
LP_CORES=0-15 #,128-159
HP_CORES=16-31 #,160-191

#64C
#  NUMA node0 CPU(s):     0-63,128-191
#  NUMA node1 CPU(s):     64-127,192-255
#LP_CORES=0-31 #,128-159
#HP_CORES=32-63 #,160-191

#MLC_LP_CORES=0-30,128-158
##MLC_LP_CORES=0-30
##LP_LATENCY_CORE=31
#MLC_HP_CORES=32-62,160-190
##MLC_HP_CORES=32-62
##HP_LATENCY_CORE=63

#32C
MLC_LP_CORES=0-14
LP_LATENCY_CORE=15

MLC_HP_CORES=16-30
HP_LATENCY_CORE=31

echo "$HP_CORES" >/sys/fs/resctrl/guaranteed/cpus_list
echo "$LP_CORES" >/sys/fs/resctrl/besteffort/cpus_list



#pare g_CLOSToMEMCLOS for hwdrc_settings_update()
#Assume MCLOS0 is highest priority and MCLOS1-2 has lower priority accordingly, MCLOS 3 with lowest priority
#Map CLOS 0-3, 8-15 and CLOS4 to MCLOS 0(HP), CLOS 5-MCLOS 1, CLOS6- MCLOS 2, CLOS7-MCLOS3(LP)
g_CLOSToMEMCLOS=0x000000C0

#MEM_CLOS_ATTRIBUTES
#config MCLOS 0 with high priority and MCLOS 3 with lowest priority
#set MEM_CLOS_ATTR#Map CLOS 0-3, 8-15 and CLOS4 to MCLOS 0(HP), CLOS 5-MCLOS 1, CLOS6- MCLOS 2, CLOS7-MCLOS3(LP)
####_EN for all 4 mclos.
#MCLOS 0(HP) with MAX delay 0x1, MIN delay 0x1, priority 0x0
#MCLOS 1, with MAX delay 0xFE, MIN delay 0x1, priority 0x5
#MCLOS 2, with MAX delay 0xFE, MIN delay 0x1, priority 0xA
#MCLOS 3(LP), with MAX delay 0xFE, MIN delay 0x1, priority 0xF

g_ATTRIBUTES_MCLOS0=0x80010100
g_ATTRIBUTES_MCLOS1=0x81FF0105
g_ATTRIBUTES_MCLOS2=0x82FF010a
g_ATTRIBUTES_MCLOS3=0x83FF010F

#equal priority
#g_ATTRIBUTES_MCLOS0=0x80FF0105
#g_ATTRIBUTES_MCLOS1=0x81FF0105
#g_ATTRIBUTES_MCLOS2=0x82FF0105
#g_ATTRIBUTES_MCLOS3=0x83FF0105

core_id=1
hwdrc_settings_update

core_id=32
hwdrc_settings_update

#enable prefetch
# for i in {0..191}; do wrmsr -p $i 0x1a4 0xf; done
wrmsr --all 0x1a4 0x0

wrmsr -p $LP_LATENCY_CORE 0x1a4 0x2f
wrmsr -p $HP_LATENCY_CORE 0x1a4 0x2f

echo off > /sys/devices/system/cpu/smt/control

for input_setponit in $(seq 0 5 255); do

        $PWD/drc_change_st.sh "$input_setponit"

        for i in {1,2,3,4,5,6,7,8,9,10,11,12}; do
                if [  $i -eq 1 ]; then
                        # if body
                        # lp 46cores(15cores, 46hyper thread)
                        wait_mlc_exit
                        #echo $$ >/sys/fs/resctrl/besteffort/tasks
                        echo "setponit $input_setponit W $i" >>lp_only.log
                        mlc -c$LP_LATENCY_CORE  -e --loaded_latency -d0 -R -k$MLC_LP_CORES -b1g -t30 >>lp_only.log

                        # # hp 46cores
                        #echo $$ >/sys/fs/resctrl/guaranteed/tasks
                        echo "setponit $input_setponit W $i" >>hp_only.log
                        mlc -c$HP_LATENCY_CORE -e --loaded_latency -d0 -R -k$MLC_HP_CORES -b1g -t30 >>hp_only.log

                        wait_mlc_exit
                        ##echo $$ >/sys/fs/resctrl/besteffort/tasks
                        echo "setponit $input_setponit W $i" >>lp_mix.log
                        time mlc -c$LP_LATENCY_CORE -e --loaded_latency -d0 -R -k$MLC_LP_CORES -b1g -t30 >>lp_mix.log &
			##wait_mlc_started /sys/fs/resctrl/besteffort/tasks 67

                        ##echo $$ >/sys/fs/resctrl/guaranteed/tasks
                        echo "setponit $input_setponit W $i" >>hp_mix.log
                        time mlc -c$HP_LATENCY_CORE -e --loaded_latency -d0 -R -k$MLC_HP_CORES -b1g -t30 >>hp_mix.log &

                        wait_mlc_exit
                        ##echo $$ >/sys/fs/resctrl/guaranteed/tasks
                        # hp 6cores
                        ##echo "setponit $input_setponit W $i" >>hp_only_light.log
                        ##mlc -c$HP_LATENCY_CORE -i$LP_LATENCY_CORE -e --loaded_latency -d0 -R -k26-28,122-124 -b1g -t20 >>hp_only_light.log

                        #wait_mlc_exit
                        ##echo $$ >/sys/fs/resctrl/besteffort/tasks
                        # lp 46cores
                        #echo "setponit $input_setponit W $i" >>lp_mix_light.log
                        #mlc -c$LP_LATENCY_CORE -i$LP_LATENCY_CORE -e --loaded_latency -d0 -R -k$MLC_LP_CORES -b1g -t20 >>lp_mix_light.log &
                        ##echo $$ >/sys/fs/resctrl/guaranteed/tasks
                        # hp 6cores
                        #echo "setponit $input_setponit W $i" >>hp_mix_light.log
                        #mlc -c$HP_LATENCY_CORE -i$HP_LATENCY_CORE -e --loaded_latency -d0 -R -k26-28,122-124 -b1g -t20 >>hp_mix_light.log &

                else
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

                fi

        done
done

#enable prefetch
# for i in {0..191}; do wrmsr -p $i 0x1a4 0x2; done
wrmsr --all 0x1a4 0x0
