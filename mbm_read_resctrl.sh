#$1 as folder to read: /sys/fs/resctrl/mon_data/mon_L3_00
#llc_occupancy  mbm_local_bytes  mbm_total_bytes

ivl=1;
local_a=`cat $1\mbm_local_bytes`;
total_b=`cat $1\mbm_total_bytes`;

sleep $ivl;

local_a_a=`cat $1\mbm_local_bytes`;
total_b_b=`cat $1\mbm_total_bytes`;

local_memBW=`echo "($local_a_a - $local_a)/1024/1024"|bc`;total_memBW=`echo "($total_b_b - $total_b)/1024/1024"|bc`;remote_memBW=`echo "$total_memBW - $local_memBW"|bc`
echo "local_memBW=$local_memBW remote_memBW=$remote_memBW"
