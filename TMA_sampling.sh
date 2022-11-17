#TMA sampling

core=$1

wrmsr -p $core 0x38d 0xb0
sleep 1;
rdmsr -p $core 0x38d

wrmsr -p $core 0x329 0x0
# fixed-function performance-monitoring counter 3 as well as PERF_METRICS when either bit 35 or 48 in IA32_PERF_GLOBAL_STATUS is set. Otherwise, PERF_METRICS may return undefined values.
wrmsr -p $core 0x30c 0x0


sleep 1;
rdmsr -p $core 0x329


#start enabled fixed cnt3 sampling on Core0
wrmsr -p $core 0x38d 0xb0b0

for i in {1..15}; do 

#wrmsr -p $core 0x329 0x0
# fixed-function performance-monitoring counter 3 as well as PERF_METRICS when either bit 35 or 48 in IA32_PERF_GLOBAL_STATUS is set. Otherwise, PERF_METRICS may return undefined values.
#wrmsr -p $core 0x30c 0x0

tma_all=`rdmsr -0 -p $core 0x329`;
echo "MSR_329h_TMA="$tma_all

tma_mb=$((16#${tma_all:0:2}));
dec_mb=`expr $tma_mb \* 100 \/ 255`;
tma_fl=$((16#${tma_all:2:2}));
dec_fl=`expr $tma_fl \* 100 \/ 255`;
tma_bm=$((16#${tma_all:4:2}));
dec_bm=`expr $tma_bm \* 100 \/ 255`;
tma_mu=$((16#${tma_all:6:2}));
dec_mu=`expr $tma_mu \* 100 \/ 255`;

echo "MB="$dec_mb"%FL="$dec_fl"%BM="$dec_fl"%MultiUops="$dec_mu"%"

tma_bb=$((16#${tma_all:8:2}));
dec_bb=`expr $tma_bb \* 100 \/ 255`;
tma_fb=$((16#${tma_all:10:2}));
dec_fb=`expr $tma_fb \* 100 \/ 255`;
tma_bs=$((16#${tma_all:12:2}));
dec_bs=`expr $tma_bs \* 100 \/ 255`;
tma_re=$((16#${tma_all:14:2}));
dec_re=`expr $tma_re \* 100 \/ 255`;

echo "BB="$dec_bb"%FB="$dec_fb"%BS="$dec_bs"%Retireing="$dec_re"%"
sleep 1;
done

#for i in {1..5}; do 
#wrmsr -p0 0x64f 0; 
#energy_1=`rdmsr -0 -p0 0x611`;
#sleep 1;
#energy_2=`rdmsr -0 -p0 0x611`;
#msr_plr=`rdmsr -0 -p0 0x64f`;
#plr_low=`echo ${msr_plr:8}`;
#energy=$((16#$energy_2-16#$energy_1));
#pkgWatt=`expr $energy / 16384`; 
#echo "pkgWatt/TDP(W):" $pkgWatt/$sku_tdp_watt" PLR:"$plr_low; 
#done 
