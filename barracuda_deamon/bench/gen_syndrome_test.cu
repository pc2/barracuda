/**
 * \file
 * \brief	This functions test the RS implmentations
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 14.8.2008
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
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>
#include <time.h>
#include <sys/time.h>
#include <math.h>

# include "gen_syndrome_test.h"

void (*local_gen_syndrome)GEN_SYNDROME;	

/**
 * Benchmarks the pure Speed of all registered implementations
 *
 * @param number_of_disks	: # of data disks
 * @param **dptrs			: datapointer
 *
 * @returns		void
 */

HOST void compare_all_implementations_one_run(int number_of_disks, void **dptrs);

HOST unsigned long mill(void);

/**
 * Benchmarks the pure Speed of all registered implementations in a loops
 *
 * @param GEN_SYNDROME				: function pointer
 * @param **implemenatation_names	: related names of each function
 *
 * @param number_of_implementations	: # of implementations
 *
 * @returns		void
 */

HOST void compare_all_implementations(	void (*gen_syndrome_list[])GEN_SYNDROME,
								 			char **implemenatation_names,
								 			int number_of_implementations)
{
printf("\"X\" ; \"Y\"\n");	
int i = 0;
int j = 0;

local_gen_syndrome = gen_syndrome_list[number_of_implementations];
void **dptrs;
	
/** 
 * Test begins with 5 Disks, because RAID6 is not worth for using with a lesser 
 * number of devices
 */
dptrs = allocate_host_example_dpointer( PAGE_SIZE, 66 );

for(j=5; j<=64; j++){
	/* Do every test 10 times for upt 64 disks*/
	for(i=0; i<10; i++){
		compare_all_implementations_one_run(j, dptrs);
		}
	}
	
deallocate_host_example_dpointer( 66, dptrs );
}



/**
 * Benchmarks the pure Speed of all registered implementations
 *
 * @param number_of_disks	: # of data disks
 * @param **dptrs			: datapointer
 *
 * @returns		void
 */

HOST void compare_all_implementations_one_run(int number_of_disks, void **dptrs)
{

/** 
 * clocks() based version, please handle with care, because it handles only
 * cpu-time 
 */
/*
unsigned long j;
unsigned long clocks_timer;
unsigned long clocks_tmp_timer;

j = 0;
clocks_timer = 0;
	
while(clocks_timer < 2*CLOCKS_PER_SEC){
	clocks_tmp_timer = clock();
		local_gen_syndrome(number_of_disks, PAGE_SIZE, dptrs);
	clocks_timer = clocks_timer = clocks_timer + (clock() - clocks_tmp_timer);
	j++;
	}

printf("%d ; %u\n", number_of_disks, (unsigned long)((PAGE_SIZE*j)/(clocks_timer/CLOCKS_PER_SEC) ) );
*/

/* high gtd time version with seconds*/
/*
double t1, t2;
int i;
unsigned long ticks;
	
//int dur = 4096 / number_of_disks;
int dur = 1000;
	
t1 = gtd_second();
for(i=0; i<dur; i++){
	local_gen_syndrome(number_of_disks, PAGE_SIZE, dptrs);
	}
t2 = gtd_second();
t2 = t2 - t1;

ticks = (unsigned long)((PAGE_SIZE*dur)/t2);
printf("%d ; %u\n", number_of_disks, ticks);
*/
	
/* high resolution gtd time version */
unsigned t1, t2;
int i;
unsigned long ticks;
	
//int dur = 4096 / number_of_disks;
int dur = 1000;
	
t1 = mill();
for(i=0; i<dur; i++){
	local_gen_syndrome(number_of_disks, PAGE_SIZE, dptrs);
	}
t2 = mill();
t2 = t2 - t1;

ticks = (unsigned long)((PAGE_SIZE*dur)/t2);
ticks = ticks * 1000;
printf("%d ; %u\n", number_of_disks, ticks);

}


HOST unsigned long mill(void)
{
struct timezone tz;
struct timeval t;
gettimeofday(&t, &tz);

return (long)( (t.tv_sec*1000) + (t.tv_usec/1000) );
}

