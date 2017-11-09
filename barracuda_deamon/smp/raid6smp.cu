/**
 * \file
 * \brief	SMP optimzed version of the gen_syndrome function
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
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


# include "raid6smp.h"
# include "../service.h"

HOST static void *proc_thread_dep_syndrome(void *arg);
HOST static inline unative_t SHLBYTE(unative_t v);
HOST static inline unative_t MASK(unative_t v);

struct thread_data{
	int disks;
	size_t bytes; 
	void **ptrs;
	int thread_id;
	int number_of_threads;
	};

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

HOST static void *proc_thread_dep_syndrome(void *arg)
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

unative_t wd0, wq0, wp0, w10, w20;

z0 = disks - 3;		// Highest data disk
p = dptr[z0+1];		// XOR parity
q = dptr[z0+2];		// RS syndrome
// RS DEPENDEND

start = (bytes/number_of_threads)*thread_id;
if( (thread_id+1) == number_of_threads){ stop = bytes; }
else{ stop  = start+(bytes/number_of_threads); }

for ( d = start ; d < stop ; d += NSIZE ){
	wq0 = wp0 = *(unative_t *)&dptr[z0][d];
	for ( z = z0-1 ; z >= 0 ; z-- ){
		wd0 = *(unative_t *)&dptr[z][d];
		wp0 ^= wd0;
		w20 = MASK(wq0);
		w10 = SHLBYTE(wq0);
		w20 &= NBYTES(0x1d);
		w10 ^= w20;
		wq0 = w10 ^ wd0;
		}
	*(unative_t *)&p[d] = wp0;
	*(unative_t *)&q[d] = wq0;
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

HOST static inline unative_t SHLBYTE(unative_t v)
{
	unative_t vv;
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

HOST static inline unative_t MASK(unative_t v)
{
	unative_t vv;

	vv = v & NBYTES(0x80);
	vv = (vv << 1) - (vv >> 7); /* Overflow on the top bit is OK */
	return vv;
}

