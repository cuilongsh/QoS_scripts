if [ "$#" -eq 3 ]
then

rmid=$1
core_start=$2
core_end=$3

echo $closid,$core_start-$core_end

for i in `seq $core_start 1 $core_end`
do
prq_value="0x000000"${rmid}
wrmsr -p$i 0xc8f $prq_value
echo  "wrmsr "-p$i 0xc8f $prq_value
rdmsr -p$i 0xc8f
done

else

#core id in socket0
rmid=$1
core_id=1


prq_value="0x"${rmid}"00000001"
wrmsr -p$core_id 0xc8d $prq_value
echo "wrmsr "-p$core_id $prq_value

for loop in {0..200}
do

sleep 1
echo "rdmsr "-p$core_id 0xc8e
rdmsr -p$core_id 0xc8e
done
fi
