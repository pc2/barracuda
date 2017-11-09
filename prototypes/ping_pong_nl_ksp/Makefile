KDIR  := /lib/modules/$(shell uname -r)/build
PWD   := $(shell pwd)
obj-m := ping.o

default: clean
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) modules
	gcc -O3 -o pong pong.c

target: clean
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) modules
	gcc -O3 -o pong pong.c
	cp ping.ko /target
	cp pong	/target
	chmod a+x /target/pong

clean:
	rm -rf *.o *.ko .*.cmd
	rm -rf *.symvers *.order *.mod.c .tmp_versions
	rm -rf pong
