obj-m += dvfs_hwp_msr.o

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all: dvfs_latency module

module:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

dvfs_latency: dvfs_latency.c
	gcc -O2 -Wall -Wextra dvfs_latency.c -o dvfs_latency -lm

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -f dvfs_latency
