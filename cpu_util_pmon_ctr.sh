#pgk Watt/TDP+ Platform limit reasons
#sku=`rdmsr -0 -p0 0x614`;
#sku_tdp=$((16#${sku:12}));
#sku_tdp_watt=`expr $sku_tdp / 8`;

for i in {1..3600}; do 
tsc_1=`rdmsr -0 -p0 0x10`;
perfmon_ctr_1=`rdmsr -0 -p0 0x30b`;

sleep 1;
tsc_2=`rdmsr -0 -p0 0x10`;
perfmon_ctr_2=`rdmsr -0 -p0 0x30b`;

perfmon_ctr_delta=$((16#$perfmon_ctr_2-16#$perfmon_ctr_1));
tsc_delta=$((16#$tsc_2-16#$tsc_1));

cpu_util=`expr $perfmon_ctr_delta \* 100 / $tsc_delta`; 
echo "cpu utilizaion:" $cpu_util "%";
#echo "perfmon_ctr_delta:"$perfmon_ctr_delta " tsc_delta=" $tsc_delta;
done 
