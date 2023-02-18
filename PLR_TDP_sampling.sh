#pgk Watt/TDP+ Platform limit reasons
sku=`rdmsr -0 -p0 0x614`;
sku_tdp=$((16#${sku:12}));
sku_tdp_watt=`expr $sku_tdp / 8`;

for i in {1..3600}; do 
wrmsr -p0 0x64f 0; 
energy_1=`rdmsr -0 -p0 0x611`;
sleep 1;
energy_2=`rdmsr -0 -p0 0x611`;
msr_plr=`rdmsr -0 -p0 0x64f`;
plr_low=`echo ${msr_plr:8}`;
energy=$((16#$energy_2-16#$energy_1));
pkgWatt=`expr $energy / 16384`; 
echo "pkgWatt/TDP(W):" $pkgWatt/$sku_tdp_watt" PLR:"$plr_low; 
done 
