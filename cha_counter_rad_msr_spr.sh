
ivl=1;
#p7_m2iosf0_380f_a=`rdmsr 0x380f`;

#socket0
core_rdmsr=60


#for m2iosf_0_base in  aa0 ab0 ac0 b30 b40 b50;
for m2iosf_0_base in  3800 3810 3820 3830 3840 3850 3860 3870 3880 3890 38A0 38B0;
do

echo $m2iosf_0_base

for((i=0; i<=15; i++));
do

reg_base=`printf %d $((16#$m2iosf_0_base))`;
reg_addr=$(($reg_base + $i))

reg_value[$i]=`rdmsr -p $core_rdmsr -d "$reg_addr"`

#echo ${reg_value[$i]}

done;

#echo 1st:${reg_value[*]}

sleep $ivl;

for((i=0; i<=15; i++));
do

reg_addr=$(($reg_base + $i))
reg_value_2[$i]=`rdmsr -p $core_rdmsr -d "$reg_addr"`

reg_value[$i]=`expr ${reg_value_2[$i]} - ${reg_value[$i]}`

#echo ${reg_value[$i]}

done;
#echo 2nd:${reg_value_2[*]}

echo delta:${reg_value[*]}
done


exit

