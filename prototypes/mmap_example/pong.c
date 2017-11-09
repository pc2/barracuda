/**
 * \file
 * \brief	Userspace client for the mmap test
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 10.10.2008
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

#include <stdio.h>
#include <memory.h>
#include <malloc.h>
#include <unistd.h>
#include <time.h>
#include <termios.h>
#include <fcntl.h>
#include <errno.h>

#include <linux/netlink.h>
#include <bits/sockaddr.h>

#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>

#include "exchange.h"

//#define SINGLETHREADED

void raid6_smp_gen_syndrome(int disks, size_t bytes, void **ptrs);
void proc_thread_dep_syndrome(int disks, size_t bytes, void **ptrs, int thread_id, int number_of_threads);

syndrome_container *get_act_syndrome_block( void );
void unget_act_syndrome_block( syndrome_container *smc );

void set_internal_vars();
int  get_number_of_phys_cpus();

int fd;
int NUMBER_OF_CPUS_INSTALLED = 1;



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
printf("test\n");
syndrome_container *ret;
char *tmp;
int i, j;
	
int disks;
size_t bytes;
void **ptrs;

set_internal_vars();
		
/* get a syndrome from kernel */
fd=open("/dev/ping", O_RDWR);
if(fd < 0){
	printf("fd opening failed !\n");
	return(-1);
	}

ret   = get_act_syndrome_block();
	
disks = ret->disks;
bytes = ret->bytes;
ptrs  = ret->ptrs;
		

#ifndef SINGLETHREADED
raid6_smp_gen_syndrome(disks, bytes, ptrs);
#endif

	
#ifdef SINGLETHREADED
proc_thread_dep_syndrome(disks, bytes, ptrs, i, number_of_threads);
	
/* modify the complete dpointer */
for(i=0; i < ret->disks; i++){
	tmp = (char *)ret->ptrs[i];
	for ( j=0 ; j < ret->bytes ; j++ ){
		tmp[j] = (ret->disks)-1-i;
		}
	}	
#endif

/* Destroy the kernel dpointer */
unget_act_syndrome_block( ret );
if(fd >= 0){ close(fd); }

return(0);
}



//______________________________________________________________________________
/**
 * //PORT
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
int i, j;
int number_of_threads = get_number_of_phys_cpus();
	
int child_pid;
int child_pids[number_of_threads];
int pipe_fd[number_of_threads][2];
int status;
	
for(i=0; i<number_of_threads; i++){
		
	if( pipe(pipe_fd[i]) != 0){
		perror("Pipe creation failed!!\n");
		return;
		}
		
	child_pid = fork();
	if(child_pid == 0){
		/* Do the child side init stuff */
		child_pid = getpid();
		close(pipe_fd[i][1]);
			
		/* get the thread ID */
		read (pipe_fd[i][0], &i, 79);
		close(pipe_fd[i][0]);

		/* execute the thread function */
		proc_thread_dep_syndrome(disks, bytes, ptrs, i, number_of_threads);
		
		return;
		}
	else{
		/* Do the main side init stuff */
		child_pids[i] = child_pid;
		close(pipe_fd[i][0]);
			
		/* send the thread ID */
		write(pipe_fd[i][1], &i, sizeof(int));
		close(pipe_fd[i][1]);
		}
	}

/* Wait for all process terminations */
for(i=0; i<number_of_threads; i++){
	waitpid(child_pids[i], &status, 0);
	}
}



/**
 * //PORT
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

void proc_thread_dep_syndrome(int disks, size_t bytes, void **ptrs, int thread_id, int number_of_threads)
{
char *tmp;
int i, j;
int start, stop;

printf("Thread %d \n", thread_id);
	
start = (bytes/number_of_threads)*thread_id;
if( (thread_id+1) == number_of_threads){ stop = bytes; }
else{ stop  = start+(bytes/number_of_threads); }
	
for(i=0; i < disks; i++){
	tmp = (char *)ptrs[i];
	for ( j=start; j<stop; j++ ){
		tmp[j] = disks-1-i;
		}
	}

}



//______________________________________________________________________________
/**
 * //PORT
 * This function returns the number of physical CPUs in the system. Mainly it 
 * returns the global variable NUMBER_OF_CPUS_INSTALLED, which is 1 per default
 * and set to the right number of CPUs by the function set_internal_vars().
 *
 * @returns	 int : number of CPUs in the system
 */

int get_number_of_phys_cpus()
{
//return NUMBER_OF_CPUS_INSTALLED;
return 8;
}



/**
 * //PORT
 * Inititalize the generation of additional system variables. This variables can
 * be get with the following functions :
 *
 * get_number_of_phys_cpus() : Get the number of SMP Processors in your system
 *
 * @returns	 void
 */

void set_internal_vars()
{
FILE *fpointer;
char buffer[256];
char *n_buffer;

/*___NUMBER_OF_CPUS_INSTALLED_________________________________________________*/
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
	
/*___NUMBER_OF_CPUS_INSTALLED_________________________________________________*/	

	
}



//______________________________________________________________________________
/**
 * //PORT
 * Get the actual syndrome container from the kernelspace
 *
 * @returns	 syndrome_container * : A pointer to the actual syndrome
 *									which should be calculated.
 */

syndrome_container *get_act_syndrome_block( )
{
int i;
unsigned int pagesizen = getpagesize();
	
syndrome_container *ret;
int disks;
size_t bytes;
	
/* map the marshalling struct */
ret = (syndrome_container *)mmap(0, sizeof(syndrome_container), PROT_READ, MAP_SHARED, fd, 0);
if(ret == MAP_FAILED){
	perror("MMAPing marshalling struct failed !\n");
	return NULL;
	}

/* allocate pointers for the disks array */
disks = ret->disks;
bytes = ret->bytes;
	
i = munmap( ret, sizeof(syndrome_container) );
if(i == -1){ 
	perror(" Unmaping marshalling struct failed !\n"); 
	return NULL;
	}

/* get data-array */
void **dptrs = malloc(disks * sizeof(void*));
	
/* map every disk pointer individually */
for(i=1; i <= disks; i++){
	dptrs[i-1] = (void *)mmap(0, bytes, PROT_WRITE, MAP_SHARED, fd, i*pagesizen);
	
	if(dptrs[i-1] == MAP_FAILED){
		printf("%d : ", i);
		perror(" MMAPing disk data failed !\n");
		return NULL;
		}
	}
	
/* malloc a syndrome container that resides at the userspace */
ret = malloc( sizeof(syndrome_container) );

/* put all arguments into the marshalling struct */
ret->disks = disks;
ret->bytes = bytes;
ret->ptrs  = dptrs;

return ret;
}



/**
 * //PORT
 * Unmap the actual syndrome container
 *
 * @param *smc		: syndrome container to unmap
 *
 * @returns			void
 */

void unget_act_syndrome_block( syndrome_container *smc )
{
int i;
int ret = 0;
int disks    = smc->disks;
size_t bytes = smc->bytes;

/* First unmap all datapointer stuff */
for(i=0; i < disks; i++){
	ret = munmap( smc->ptrs[i-1], sizeof(syndrome_container) );
	}

/* Free the pointer array for the disk streams */
free(smc->ptrs);

/* At last, free the marshalling struct */
free(smc);
}
