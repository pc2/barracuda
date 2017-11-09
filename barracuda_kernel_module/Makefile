CC                  := gcc
KDIR                := /lib/modules/$(shell uname -r)/build
PWD                 := $(shell pwd)
obj-m               := raid6cuda_test.o 
raid6cuda_test-objs := raid6cuda.o raid6cuda_tst.o

default: clean
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) modules

clean:
	rm -rf *.o *.ko .*.cmd
	rm -rf *.symvers *.order *.mod.c .tmp_versions

count:
	wc -l `find -name '*.cu' && find -name '*.c' &&  find -name '*.h'`
