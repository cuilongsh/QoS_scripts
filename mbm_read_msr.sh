#assign rmid
for((core=0;core<`cat /proc/cpuinfo |grep processor|wc -l`;core++));do wrmsr -p $core 0xc8f $core;done;

ivl=1;
wrmsr 0xc8d 0x000000003;
# IA32_QM_EVTSEL ,0x03 for local memory bandwidth
#63:63,Error IA32_PQR_QM_EVTSEL. —If 1, indicates and unsupported RMID or event type was written to
#62:62 Unavailable monitored for this resource or RMID. —If 1, indicates data for this RMID is not available or not
local_a=`rdmsr 0xc8e`;
# IA32_QM_CTR,61:0 , Resource Monitored Data
wrmsr 0xc8d 0x000000002;
# IA32_QM_EVTSEL ,0x02 for total memory bandwidth
total_b=`rdmsr 0xc8e`;

sleep $ivl;

wrmsr 0xc8d 0x000000003;local_a_a=`rdmsr 0xc8e`;
wrmsr 0xc8d 0x000000002;total_b_b=`rdmsr 0xc8e`;

local_a_d=`printf %d 0x$local_a`;total_b_d=`printf %d 0x$total_b`;
local_a_a_d=`printf %d 0x$local_a_a`;total_b_b_d=`printf %d 0x$total_b_b`;
local_memBW=`echo "($local_a_a_d - $local_a_d)/16"|bc`;total_memBW=`echo "($total_b_b_d - $total_b_d)/14.2"|bc`;remote_memBW=`echo "$total_memBW - $local_memBW"|bc`
echo "local_memBW=$local_memBW remote_memBW=$remote_memBW"
