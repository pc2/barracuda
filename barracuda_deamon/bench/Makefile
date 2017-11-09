CC            = nvcc
CFLAGS        = -O3
LDFLAGS       = 
INCLUDES     := -I$(KERNELSOURCE)/drivers/md/


all: service.o
	$(CC) -c cuda_xor_test.cu -o cuda_xor_test.o $(CFLAGS)
	$(CC) -o cuda_xor_test cuda_xor_test.o service.o $(CFLAGS)

	$(CC) -c cuda_shift_test.cu -o cuda_shift_test.o $(CFLAGS)
	$(CC) -o cuda_shift_test cuda_shift_test.o service.o $(CFLAGS)

service.o: ../service.cu
	$(CC) $(INCLUDES) -o service.o $(CFLAGS) -c ../service.cu

clean:
	rm -rf $(EXECUTABLE)
	rm -rf *.o
	rm -rf cuda_xor_test cuda_shift_test
