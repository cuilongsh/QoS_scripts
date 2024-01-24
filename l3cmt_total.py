import os
import sys

global l3_cmt_on_socket
l3_cmt_on_socket=[0,0]

def get_llc_occupancy(mon_dir):
	sum = 0
	socket = 0
	for mon_data_die in os.listdir(mon_dir):
		fn = os.path.join(mon_dir, mon_data_die, "llc_occupancy")
		with open(fn) as f:
			llc = int(f.readline().split()[0])
		sum += llc
		l3_cmt_on_socket[socket] += llc
		socket += 1
	print (mon_dir,l3_cmt_on_socket)
	return sum

def get_l3_size(resctrl_dir):
	
	fn = os.path.join(resctrl_dir, "size")
	with open(fn) as f:
		l3_size_lines=f.readline().split(";")
		s0=int(l3_size_lines[0].split("=")[1])
		s1=int(l3_size_lines[1].split("=")[1])
	sum=s0+s1
	print("socket 0 L3 size=",s0)
	print("socket 1 L3 size=",s1)

	return sum


def main(argv):
	RESCTRL_MOUNT = '/sys/fs/resctrl'
	total=0
	for item in os.listdir(RESCTRL_MOUNT):
		d = os.path.join(RESCTRL_MOUNT, item, "mon_data")
		if os.path.isdir(d):
			llc = get_llc_occupancy(d)
			print(item,llc)
			total += llc
	#d = os.path.join('/sys/fs/resctrl', "mon_data")
	d = "/sys/fs/resctrl/mon_data"
	if os.path.isdir(d):
		llc = get_llc_occupancy(d)
		print("root",llc)
		total += llc
	print("total cmt =",total)
	
	d= "/sys/fs/resctrl/"
	l3_size=get_l3_size(d)
	print("total l3 size=",l3_size)
	
	print("Socket 0,cmt=",l3_cmt_on_socket[0])
	print("Socket 1,cmt=",l3_cmt_on_socket[1])

	
if __name__ == "__main__":
    main(sys.argv[1:])

