closid=$1
core_start=$2
core_end=$3

echo $closid,$core_start-$core_end

for i in `seq $core_start 1 $core_end`
do
prq_value="0x"${closid}"00000000"
wrmsr -p$i 0xc8f $prq_value
#echo -p$i,$prq_value
echo core=$i
rdmsr -p$i 0xc8f
done

