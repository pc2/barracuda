COMPILER := gcc
#COMPILER := nvcc
CC := $(COMPILER)

binary: clean
	make -C barracuda_deamon/ CC=$(COMPILER)
	cp barracuda_deamon/baracuda_deamon bin/
	cp tools/scripts/barracuda bin/	
	make -C barracuda_kernel_module/ CC=gcc
	cp barracuda_kernel_module/raid6cuda_test.ko bin/

ifeq ($(COMPILER),nvcc)
	@echo "---------------------------------------------------------------"
	@echo " CUDA C MODE -> compiling cuda_memcheck"
	@echo " Modify COMPILER in this Makefile for another Compiler"
	@echo "---------------------------------------------------------------"
	make -C tools/cuda_memcheck/
	cp tools/cuda_memcheck/cuda_memcheck bin/
else
	@echo "---------------------------------------------------------------"
	@echo " ANSI C MODE "
	@echo " Modify COMPILER in this Makefile for another Compiler"
	@echo "---------------------------------------------------------------"
endif


install: binary
	mkdir /opt/barracuda
	mv bin/* /opt/barracuda
	ln -s /opt/barracuda/barracuda /etc/init.d/barracuda
ifeq ($(COMPILER),nvcc)
	ln -s /opt/barracuda/cuda_memcheck /bin/cuda_memcheck
endif
	
deinstall:
	rm -rf /opt/barracuda
	rm -rf /etc/init.d/barracuda
ifeq ($(COMPILER),nvcc)
	rm -rf /bin/cuda_memcheck
endif

doxy: barracuda.doxy
	doxygen barracuda.doxy
#	make -C doc/latex/

count: clean
	wc -l `find -name '*.cu' && find -name '*.c' &&  find -name '*.h'`

clean:
	make -C barracuda_deamon/ clean
	make -C barracuda_kernel_module/ clean
	make -C tools/cuda_memcheck/ clean
	rm -rf bin/*
	rm -rf doc/*

dist: clean
	tar -cjf ../$(EXECUTABLE).tar.bz2 *	
# DO NOT DELETE
