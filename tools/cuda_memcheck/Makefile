################################################################################
#
# Build script for cuda_memcheck. 
# Please download the cuda 1.1 SDK for including and compiling this source
# 
################################################################################

EXECUTABLE   := cuda_memcheck
CC           := nvcc
CFLAGS       := -O3 -g
LIB          := -lm -lcuda
OBJECTS      := 

################################################################################
#
# CUDA Build directives
#
################################################################################

$(EXECUTABLE): clean
	$(CC) -o $(EXECUTABLE) $(LIB) $(EXECUTABLE).cu

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
	rm -rf $(EXECUTABLE)
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
