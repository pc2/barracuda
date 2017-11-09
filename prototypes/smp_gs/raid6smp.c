/**
 * \file
 * \brief	SMP Cache Benchmark
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: BETA\n
 * Date of creation : 20.8.2008
 *
 */

/*****************************************************************
 *
 * Barracuda is a experimental microdriver extension to the 
 * linux-kernel that is able to outsource common functions to
 * the userspace. It was intensionally designed to accelerate
 * CPU-intensive Tasks on a GPU.
 *
 * Copyright (C) 2009 Dominic Eschweiler
 *
 * This program is free software; you can redistribute it and/or 
 * modify it under the terms of the GNU General Public License as 
 * published by the Free Software Foundation; either only GPLv2 - 
 * version 2 of the License.
 *
 * This program is distributed in the hope that it will be useful, 
 * but WITHOUT ANY WARRANTY; without even the implied warranty of 
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the 
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public 
 * License along with this program; 
 * if not, see <http://www.gnu.org/licenses/>.
 *
 *****************************************************************/

#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>
#include <math.h>
#include <time.h>

#include <sys/time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <pthread.h>

#include <linux/types.h>

#define BITS_PER_LONG __WORDSIZE
#define NSIZE 8
#define NBYTES(x) ((x) * 0x0101010101010101UL)
#define TIMING gtd_second()


typedef __u8 u8;
typedef __u16 u16;
typedef __u32 u32;
typedef __u64 u64;

double gtd_second(void);
double second(void);
void **allocate_host_example_dpointer( int bytes, int number_of_disks );
void deallocate_host_example_dpointer( int number_of_disks, void **dptrs );
void print_dpointer(int disks, int bytes, void **ptrs);
void set_internal_vars();
int get_number_of_phys_cpus();
void raid6_smp_gen_syndrome(int disks, size_t bytes, void **ptrs);
static void *proc_thread_dep_syndrome(void *arg);
static inline u64 SHLBYTE(u64 v);
static inline u64 MASK(u64 v);


struct thread_data{
	int disks;
	size_t bytes; 
	void **ptrs;
	int thread_id;
	int number_of_threads;
	};

/**
 * mmap test main routine
 *
 * @param argc		: # of arguments
 * @param **argv	: Array of arguments
 *
 * @returns			EXIT_FAILURE on error, EXIT_SUCCESS on no error
 */

int main(int argc, char **argv)
{
unsigned int begin = 4096;
unsigned int end = 2097152;
unsigned long j;
double timer, tmp_timer;

void **dptrs;
dptrs = allocate_host_example_dpointer( end, 5 );

printf("X; Y\n");

while( begin <= end){
	tmp_timer = TIMING;
	for(j=0; j < 10000; j++){
		raid6_smp_gen_syndrome(5, begin, dptrs);
		}
	tmp_timer = TIMING - tmp_timer;
	timer = timer + tmp_timer;
	
	printf("%u ; %u\n", begin, (unsigned long)((begin*j)/timer) );

	begin = begin*2;
	}

deallocate_host_example_dpointer( 5, dptrs );
}

/**
 * This is the SMP-version of the gen_syndrome function. It uses the systemcall
 * fork() for the thread as process execution.
 *
 * @param	disks 				: number of disks
 * @param	bytes				: number of bytes per disks
 * @param	**ptrs				: pointers to the disks data
 *
 * @returns	 void
 */

void raid6_smp_gen_syndrome(int disks, size_t bytes, void **ptrs)
{
//printf("SMP\n");

int i;
int number_of_threads = get_number_of_phys_cpus();

//printf("%d\n", number_of_threads);
	
pthread_t threads[number_of_threads];
struct thread_data thread_data_array[number_of_threads];
int rc;
void *status;
   
for(i=0; i<number_of_threads; i++){
	thread_data_array[i].disks				= disks;
	thread_data_array[i].bytes				= bytes; 
	thread_data_array[i].ptrs				= ptrs;
	thread_data_array[i].thread_id			= i;
	thread_data_array[i].number_of_threads	= number_of_threads;

	rc = pthread_create(&threads[i], NULL, proc_thread_dep_syndrome, (void *)&thread_data_array[i]);

	if(rc){
		printf("ERROR; return code from pthread_create() is %d\n", rc);
		exit(-1);
		}

	}
	
for(i=0; i<number_of_threads; i++){
	rc = pthread_join(threads[i], &status);
	if (rc){
		printf("ERROR; return code from pthread_join() is %d\n", rc);
		exit(-1);
		}
	}

//pthread_exit(NULL);

}



/**
 * This function is the real thread-code which calculates the syndromes.
 *
 * @param	disks 				: number of disks
 * @param	bytes				: number of bytes per disks
 * @param	**ptrs				: pointers to the disks data
 * @param	thread_id			: number of the thread where this function is executed
 * @param	number_of_threads	: number of all threads
 *
 * @returns	 void
 */

static void *proc_thread_dep_syndrome(void *arg)
{
int start, stop;
struct thread_data *data;
data = (struct thread_data *)arg;

int disks				= data->disks;
size_t bytes			= data->bytes;
void **ptrs				= data->ptrs;
int thread_id			= data->thread_id;
int number_of_threads	= data->number_of_threads;


// RS DEPENDEND
u8 **dptr = (u8 **)ptrs;
u8 *p, *q;
int d, z, z0;

u64 wd0, wq0, wp0, w10, w20;

z0 = disks - 3;		// Highest data disk
p = dptr[z0+1];		// XOR parity
q = dptr[z0+2];		// RS syndrome
// RS DEPENDEND

start = (bytes/number_of_threads)*thread_id;
if( (thread_id+1) == number_of_threads){ stop = bytes; }
else{ stop  = start+(bytes/number_of_threads); }

for ( d = start ; d < stop ; d += NSIZE ){
	wq0 = wp0 = *(u64 *)&dptr[z0][d];
	for ( z = z0-1 ; z >= 0 ; z-- ){
		wd0 = *(u64 *)&dptr[z][d];
		wp0 ^= wd0;
		w20 = MASK(wq0);
		w10 = SHLBYTE(wq0);
		w20 &= NBYTES(0x1d);
		w10 ^= w20;
		wq0 = w10 ^ wd0;
		}
	*(u64 *)&p[d] = wp0;
	*(u64 *)&q[d] = wq0;
	}

pthread_exit(NULL);
}



/**
 * The SHLBYTE() operation shifts each byte left by 1, *not*
 * rolling over into the next byte
 *
 * @param v		: Integer which should be shifted
 *
 * @returns		The shifted integer
 */

static inline u64 SHLBYTE(u64 v)
{
	u64 vv;
	vv = (v << 1) & NBYTES(0xfe);
	return vv;
}



/**
 * The MASK() operation returns 0xFF in any byte for which the high
 * bit is 1, 0x00 for any byte for which the high bit is 0.
 *
 * @param v		: Integer which should be processed
 *
 * @returns		0xFF = high bit is 1, 0x00 = high bit is 0
 */

static inline u64 MASK(u64 v)
{
	u64 vv;

	vv = v & NBYTES(0x80);
	vv = (vv << 1) - (vv >> 7); /* Overflow on the top bit is OK */
	return vv;
}

static int NUMBER_OF_CPUS_INSTALLED = 1;

/**
 * The gtd_second function returns the amount of time, where the process 
 * is running. It uses the propper glibc function gettimeofday() which
 * which extracts from the RTC
 *
 * @returns		Time
 */

double gtd_second(void)
{
	struct timezone tz;
	struct timeval t;
	gettimeofday(&t, &tz);

	return (double) t.tv_sec + ((double)t.tv_usec/1e6);
}



/**
 * The gtd_second function returns the amount of time, where the process 
 * is running. It uses the propper glibc function gettimeofday() which
 * extracts from the RTC
 *
 * @returns		Time
 */

double second(void)
{
double secs;
clock_t Time;
Time = clock();
secs = (double)Time / (double)CLOCKS_PER_SEC;
return secs ;
}



/**
 * Generates a test datapointer for the gen_syndrome function, which can be used
 * by the validator or benchmarking functions.
 *
 * @param bytes				: # of bytes
 * @param number_of_disks	: Number of virtual data disks
 *
 * @returns				Datapointers were the gft an syndrome gets saved in
 */

void **allocate_host_example_dpointer( int bytes, int number_of_disks )
{
/* Variables */
int i;
void **dptrs;
	
#ifdef DEBUG_LEVEL_2
	printf("-= DEBUG 2 =- \n");
	print_dpointer( number_of_disks, PAGE_SIZE, dptrs);
	printf("-= DEBUG 2 =- \n");
#endif
	
/* Set virtual disk data */
dptrs = (void **)malloc( (number_of_disks)*sizeof(void *) );
for ( i = 0; i < number_of_disks; i++ ){
	dptrs[i] = (void *)malloc(bytes*sizeof(u8));
	}

return dptrs;
}



/**
 * Deallocates the example dpointer
 *
 * @param number_of_disks	: Number of virtual data disks
 * @param **dptrs			: datapointer
 *
 * @returns				Datapointers were the gft an syndrome gets saved in
 */

void deallocate_host_example_dpointer( int number_of_disks, void **dptrs )
{
/* Variables */
int i;

/* Free virtual disk data */
for ( i = 0 ; i < number_of_disks ; i++ ){
	free(dptrs[i]);
	}
free(dptrs);
}



/**
 * Prints a dpointer to the console.
 *
 * @param disks			: # of disks
 * @param bytes			: # of bytes
 * @param **ptrs		: Datapointers were the gft an syndrome gets saved in
 *
 * @returns		# of disks
 */

void print_dpointer(int disks, int bytes, void **ptrs)
{
int i;
	
u8 **dptrs = (u8 **)ptrs;
u8 *xor_d  = dptrs[disks];
u8 *syn_d  = dptrs[disks+1];

for(i=0; i < bytes; i++){
	printf("%d %d ", xor_d[i], syn_d[i]);
	}

printf("\n");

}



/**
 * Inititalize the generation of additional system variables. This variables can
 * be get with the following functions :
 *
 * get_number_of_phys_cpus() : Get the number of SMP Processors in your system
 *
 * @param    void
 *
 * @returns	 void
 */

void set_internal_vars()
{
FILE *fpointer;
char buffer[256];
char *n_buffer;

/* initially set the number of cpus to 1 */
NUMBER_OF_CPUS_INSTALLED = 1;
	
/* open the sysfs file that shows the number of cpus */
fpointer = fopen("/sys/devices/system/cpu/online", "r");	
if(fpointer == NULL){
	/**
	 * The CPU info dir exists only if there are multiple CPUs. Therfore, if the
	 * opening fails, the default value 1 is used. 
	 */
	return;
	}
else{
	/**
	 * In this case, the infodir exists and the value of cpus can be simply
	 * extracted from 
	 */
	fgets( (char *)&buffer, 256, fpointer);
	strtok((char *)&buffer, "-");
	n_buffer = strtok(NULL, "-");
	
	NUMBER_OF_CPUS_INSTALLED = atoi(n_buffer)+1;
	
	fclose(fpointer);
	}
	
}



/**
 * This function returns the number of physical CPUs in the system. Mainly it 
 * returns the global variable NUMBER_OF_CPUS_INSTALLED, which is 1 per default
 * and set to the right number of CPUs by the function set_internal_vars().
 *
 * @param    void
 *
 * @returns	 int : number of CPUs in the system
 */

int get_number_of_phys_cpus()
{
return NUMBER_OF_CPUS_INSTALLED;
//return 8;
}
