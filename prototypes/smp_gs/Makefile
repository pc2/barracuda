default: clean
	gcc -O3 -lpthread -lm -o test raid6smp.c

clean:
	rm -rf *.o *.ko .*.cmd
	rm -rf *.symvers *.order *.mod.c .tmp_versions
	rm -rf pong
