##Resctrl setup
mount resctrl -t resctrl /sys/fs/resctrl/
mkdir -p /sys/fs/resctrl/COS{1..7}

echo "0-19,120-139" >/sys/fs/resctrl/COS1/cpus_list
echo "20-39,140-159" >/sys/fs/resctrl/COS4/cpus_list

cat /sys/fs/resctrl/COS1/cpus_list
cat /sys/fs/resctrl/COS4/cpus_list
