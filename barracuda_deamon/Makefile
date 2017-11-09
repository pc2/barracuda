################################################################################
#
# Build script for baracuda. 
# Please download the cuda 1.1 SDK for including and compiling this source
# 
################################################################################

EXECUTABLE   := baracuda_deamon
KERNELSOURCE := /lib/modules/`uname -r`/source

################################################################################
# 
# Compiler related stuff
#
################################################################################

SPLINT_FLAGS := $(INCLUDES) -preproc +weak +boundswrite -nestcomment +ignorequals

ifeq ($(CC),gcc)
	CFLAGS   := -O3 -g -D NOCUDA -D MAIN_IS_ACTIVE
	INCLUDES := -I$(KERNELSOURCE)/drivers/md/
	LIB      := -lm -lpthread
	OBJECTS  := baracuda_deamon.o service.o validator.o benchmarker.o gen_syndrome_test.o userspace_driver.o
	OBJECTS2 := raid6vanilla.o raid6smp.o raid6dummy.o raid6multrs.o
else
	CFLAGS   := -O3 -g -D MAIN_IS_ACTIVE
	INCLUDES := -I$(KERNELSOURCE)/drivers/md/
	LIB      := -lm -lcuda
	OBJECTS  := baracuda_deamon_cuda.o service_cuda.o validator_cuda.o benchmarker_cuda.o userspace_driver_cuda.o
	OBJECTS2 := raid6vanilla_cuda.o raid6smp_cuda.o raid6cuda_cuda.o raid6dummy_cuda.o raid6multrs_cuda.o
    OBJECTS3 := cuda_xor_test.o cuda_shift_test.o gen_syndrome_test_cuda.o
endif

################################################################################
#
# Generic compiler dependend compile.
#
################################################################################

$(EXECUTABLE): clean
	find -name '*.cu' -exec ../linkswitch.sh {} \;

ifeq ($(CC),gcc)
	@echo "---------------------------------------------------------------"
	@echo " ANSI C MODE "
	@echo "---------------------------------------------------------------"

	make $(EXECUTABLE)_ANSI
else
	@echo "---------------------------------------------------------------"
	@echo " CUDA MODE "
	@echo "---------------------------------------------------------------"

	make $(EXECUTABLE)_CUDA
endif


################################################################################
#
# ANSI C Build directives
#
################################################################################

$(EXECUTABLE)_ANSI: $(OBJECTS) $(OBJECTS2)
	$(CC) -o $(EXECUTABLE) $(OBJECTS) $(OBJECTS2) $(LIB)

baracuda_deamon.o: baracuda_deamon.c
	$(CC) $(CFLAGS) -c baracuda_deamon.c -o baracuda_deamon.o $(INCLUDES)

service.o: service.c
	$(CC) $(CFLAGS) -c service.c -o service.o $(INCLUDES)

validator.o: validator.c
	$(CC) $(CFLAGS) -c validator.c -o validator.o $(INCLUDES)

benchmarker.o: benchmarker.c
	$(CC) $(CFLAGS) -c benchmarker.c -o benchmarker.o $(INCLUDES)

raid6vanilla.o: vanilla/raid6vanilla.c
	$(CC) $(CFLAGS) -c vanilla/raid6vanilla.c -o raid6vanilla.o $(INCLUDES)

raid6smp.o: smp/raid6smp.c
	$(CC) $(CFLAGS) -c smp/raid6smp.c -o raid6smp.o $(INCLUDES)

raid6dummy.o: dummy/raid6dummy.c
	$(CC) $(CFLAGS) -c dummy/raid6dummy.c -o raid6dummy.o $(INCLUDES)

raid6multrs.o: multrs/raid6multrs.c
	$(CC) $(CFLAGS) -c multrs/raid6multrs.c -o raid6multrs.o $(INCLUDES)

gen_syndrome_test.o: bench/gen_syndrome_test.c
	$(CC) $(CFLAGS) -c bench/gen_syndrome_test.c -o gen_syndrome_test.o $(INCLUDES)

userspace_driver.o: userspace_driver.c
	$(CC) $(CFLAGS) -c userspace_driver.c -o userspace_driver.o $(INCLUDES)


################################################################################
#
# CUDA Build directives
#
################################################################################

$(EXECUTABLE)_CUDA: clean $(OBJECTS) $(OBJECTS2) $(OBJECTS3)
	$(CC) -o $(EXECUTABLE) $(OBJECTS) $(OBJECTS2) $(OBJECTS3) $(LIB)

baracuda_deamon_cuda.o: baracuda_deamon.cu
	$(CC) $(CFLAGS) -c baracuda_deamon.cu -o baracuda_deamon_cuda.o $(INCLUDES)

service_cuda.o: service.cu
	$(CC) $(CFLAGS) -c service.cu -o service_cuda.o $(INCLUDES)

validator_cuda.o: validator.cu
	$(CC) $(CFLAGS) -c validator.cu -o validator_cuda.o $(INCLUDES)

benchmarker_cuda.o: benchmarker.cu
	$(CC) $(CFLAGS) -c benchmarker.cu -o benchmarker_cuda.o $(INCLUDES)

raid6vanilla_cuda.o: vanilla/raid6vanilla.cu
	$(CC) $(CFLAGS) -c vanilla/raid6vanilla.cu -o raid6vanilla_cuda.o $(INCLUDES)

raid6cuda_cuda.o: cuda/raid6cuda.cu
	$(CC) $(CFLAGS) -c cuda/raid6cuda.cu -o raid6cuda_cuda.o $(INCLUDES)

raid6smp_cuda.o: smp/raid6smp.cu
	$(CC) $(CFLAGS) -c smp/raid6smp.cu -o raid6smp_cuda.o $(INCLUDES)

raid6dummy_cuda.o: dummy/raid6dummy.cu
	$(CC) $(CFLAGS) -c dummy/raid6dummy.cu -o raid6dummy_cuda.o $(INCLUDES)

raid6multrs_cuda.o: multrs/raid6multrs.cu
	$(CC) $(CFLAGS) -c multrs/raid6multrs.cu -o raid6multrs_cuda.o $(INCLUDES)

cuda_xor_test.o: bench/cuda_xor_test.cu
	$(CC) $(CFLAGS) -c bench/cuda_xor_test.cu -o cuda_xor_test.o $(INCLUDES)

cuda_shift_test.o: bench/cuda_shift_test.cu
	$(CC) $(CFLAGS) -c bench/cuda_shift_test.cu -o cuda_shift_test.o $(INCLUDES)

gen_syndrome_test_cuda.o: bench/gen_syndrome_test.cu
	$(CC) $(CFLAGS) -c bench/gen_syndrome_test.cu -o gen_syndrome_test_cuda.o $(INCLUDES)

userspace_driver_cuda.o: userspace_driver.cu
	$(CC) $(CFLAGS) -c userspace_driver.cu -o userspace_driver_cuda.o $(INCLUDES)

################################################################################
#
# Source cleaning an debugging directives 
#
################################################################################

splint:
	splint $(SPLINT_FLAGS) baracuda_deamon.c	
	splint $(SPLINT_FLAGS) vanilla/raid6vanilla.c

memory_check: clean $(EXECUTABLE)
	valgrind --tool=memcheck --leak-check=full ./$(EXECUTABLE)

count:
	wc -l `find -name '*.cu' && find -name '*.c' &&  find -name '*.h'`

clean:
	find -name '*~' -exec rm {} \;
	find -name '*.bak' -exec rm {} \;
	find -name '*.o' -exec rm {} \;
	find -name 'a.out' -exec rm {} \;
	rm -rf baracuda_deamon
	find . -lname '*' -exec rm {} \;

################################################################################
#
# HELP!!
#
################################################################################

help:
	@echo This Makefile provides :
	@echo make              : build the deamon
	@echo make splint       : provide a splint trace
	@echo make memory_check : provide a valgrind memory trace
	@echo make count        : LOC
	@echo make clean        : clean source from .o ...
