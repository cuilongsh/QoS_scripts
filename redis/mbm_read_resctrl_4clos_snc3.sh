#llc_occupancy  mbm_local_bytes  mbm_total_bytes

#currentclos="COS1"
for currentclos in {1,4};
do
clos_mbm_path="/sys/fs/resctrl/COS$currentclos/mon_data/mon_L3_00/"

local_a[$currentclos]=`cat $clos_mbm_path/mbm_local_bytes`;
total_b[$currentclos]=`cat $clos_mbm_path/mbm_total_bytes`;

local_a_snc0[$currentclos]=`cat $clos_mbm_path/mon_sub_L3_00/mbm_local_bytes`
local_a_snc1[$currentclos]=`cat $clos_mbm_path/mon_sub_L3_01/mbm_local_bytes`
local_a_snc2[$currentclos]=`cat $clos_mbm_path/mon_sub_L3_02/mbm_local_bytes`
done

sleep 1;


current_MBA=`pqos --iface=msr -s |grep "MBA COS"| head -n 16`
#echo $current_MBA
# Extract the values for COS0, COS1, COS2, and COS3 for Socket 0
cos_MBA[1]=$(echo "$current_MBA" | grep -oP 'COS1 => \K\d+%')
cos_MBA[2]=$(echo "$current_MBA" | grep -oP 'COS2 => \K\d+%')
cos_MBA[3]=$(echo "$current_MBA" | grep -oP 'COS3 => \K\d+%')
cos_MBA[4]=$(echo "$current_MBA" | grep -oP 'COS4 => \K\d+%')

#echo ${cos_MBA[1]},${cos_MBA[2]},${cos_MBA[3]},${cos_MBA[4]}

for currentclos in {1,4};
do
clos_mbm_path="/sys/fs/resctrl/COS$currentclos/mon_data/mon_L3_00/"

local_a_a[$currentclos]=`cat $clos_mbm_path/mbm_local_bytes`;
total_b_b[$currentclos]=`cat $clos_mbm_path/mbm_total_bytes`;

local_a_a_snc0[$currentclos]=`cat $clos_mbm_path/mon_sub_L3_00/mbm_local_bytes`
local_a_a_snc1[$currentclos]=`cat $clos_mbm_path/mon_sub_L3_01/mbm_local_bytes`
local_a_a_snc2[$currentclos]=`cat $clos_mbm_path/mon_sub_L3_02/mbm_local_bytes`

local_memBW=`echo "(${local_a_a[$currentclos]} - ${local_a[$currentclos]})/1024/1024"|bc`;total_memBW=`echo "(${total_b_b[$currentclos]} - ${total_b[$currentclos]})/1024/1024"|bc`;remote_memBW=`echo "$total_memBW - $local_memBW"|bc`

snc0_local=`echo "(${local_a_a_snc0[$currentclos]} - ${local_a_snc0[$currentclos]})/1024/1024"|bc`;
snc1_local=`echo "(${local_a_a_snc1[$currentclos]} - ${local_a_snc1[$currentclos]})/1024/1024"|bc`;
snc2_local=`echo "(${local_a_a_snc2[$currentclos]} - ${local_a_snc2[$currentclos]})/1024/1024"|bc`;


echo "COS$currentclos:local_memBW=$local_memBW SNC=$snc0_local,$snc1_local,$snc2_local remote_memBW=$remote_memBW , MBA= ${cos_MBA[$currentclos]}"

done

