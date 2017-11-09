/**
 * \file
 * \brief	library for helper functions
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
 * Date of creation : 19.5.2008
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

#include <linux/types.h>

#include "service.h"

static int NUMBER_OF_CPUS_INSTALLED = 1;

/**
 * The gtd_second function returns the amount of time, where the process 
 * is running. It uses the propper glibc function gettimeofday() which
 * which extracts from the RTC
 *
 * @returns		Time
 */

HOST double gtd_second(void)
{
	struct timezone tz;
	struct timeval t;
	gettimeofday(&t, &tz);

	return (double) t.tv_sec + ((double)t.tv_usec/1e6);
}



/**
 * The second function returns the amount of time, where the process 
 * is running. It uses the propper glibc function gettimeofday() which
 * extracts from the RTC
 *
 * @returns		Time
 */

HOST double second(void)
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

HOST void **allocate_host_example_dpointer( int bytes, int number_of_disks )
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

HOST void deallocate_host_example_dpointer( int number_of_disks, void **dptrs )
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

HOST void print_dpointer(int disks, int bytes, void **ptrs)
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
 * get_number_of_phys_cpus() : Get the number of SMP Processors in your system
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
 * @returns	 int : number of CPUs in the system
 */

int get_number_of_phys_cpus()
{
return NUMBER_OF_CPUS_INSTALLED;
}
