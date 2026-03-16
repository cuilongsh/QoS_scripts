##script for Client
ip addr add 10.0.0.101/30 dev ens6f0np0
#disable all Cstate ,except C1
cpupower idle-set -D 2
systemctl stop irqbalance
cd /home/longcui
./check-elc.sh --performance_elc
cd /home/longcui/ethernet-linux-ice/scripts
./set_irq_affinity 10-19,154-163 ens6f0np0

