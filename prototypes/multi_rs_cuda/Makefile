CC = nvcc
CFLAGS = -g -O3 -lm -lcuda

rs_encoder: clean $(OBJECTS)
	$(CC) -o rs_encoder $(CFLAGS) rs_encoder.cu

clean:
	find -name '*~' -exec rm {} \;
	find -name '*.bak' -exec rm {} \;
	find -name '*.o' -exec rm {} \;
	find -name 'a.out' -exec rm {} \;
	rm -rf rs_encoder
	find . -lname '*' -exec rm {} \;
