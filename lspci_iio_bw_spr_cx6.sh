ivl=1


for ((loop=1; loop<=100; loop++));
do

i=0
sleep $ivl
#for mesh2pcie_i in 00:00.1 16:00.1 30:00.1 4a:00.1 64:00.1 80:00.1 97:00.1 b0:00.1 c9:00.1 e2:00.1;
for mesh2pcie_i in 00:00.1 15:00.1 26:00.1 37:00.1 48:00.1 59:00.1 6a:00.1 6f:00.1 74:00.1 79:00.1 80:00.1 97:00.1 a7:00.1 b7:00.1 c7:00.1 d7:00.1 e7:00.1 ec:00.1 f1:00.1 f6:00.1;
do

dump_140=`lspci -xxxx -s $mesh2pcie_i |grep "140:" `
###echo $dump_140
iio_bw_counter_hex=`echo $dump_140|awk '{print $9 $8 $7 $6}'`
iio_bw_counter_dec[$i]=`printf %d $((16#$iio_bw_counter_hex))`

#echo $iio_bw_counter_hex
#echo ${iio_bw_counter_dec[$i]}
i=$i+1

done

###echo init counter: ${iio_bw_counter_dec[*]}

##echo sleep $ivl second.
sleep $ivl;

i=0
#for mesh2pcie_i in 00:00.1 16:00.1 30:00.1 4a:00.1 64:00.1 80:00.1 97:00.1 b0:00.1 c9:00.1 e2:00.1;
for mesh2pcie_i in 00:00.1 15:00.1 26:00.1 37:00.1 48:00.1 59:00.1 6a:00.1 6f:00.1 74:00.1 79:00.1 80:00.1 97:00.1 a7:00.1 b7:00.1 c7:00.1 d7:00.1 e7:00.1 ec:00.1 f1:00.1 f6:00.1;
do

dump_140=`lspci -xxxx -s $mesh2pcie_i |grep "140:" `
###echo $dump_140
iio_bw_counter_hex=`echo $dump_140|awk '{print $9 $8 $7 $6}'`
iio_bw_counter_dec_2[$i]=`printf %d $((16#$iio_bw_counter_hex))`

iio_bw_counter_per_second[$i]=`expr ${iio_bw_counter_dec_2[$i]} - ${iio_bw_counter_dec[$i]}`

#echo $iio_bw_counter_hex
#echo ${iio_bw_counter_dec_2[$i]}
i=$i+1

done

echo delta:${iio_bw_counter_per_second[*]}
done
