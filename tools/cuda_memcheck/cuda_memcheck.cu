/**
 * \file
 * \brief	CUDA-Memorytest
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
 * Date of creation : 20.11.2008
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
#include <sched.h>
#include <signal.h>
#include <sys/wait.h>
#include <syslog.h>

#include <cuda_runtime_api.h>
#include <cuda.h>

int gen_pattern(const char *output_tag, unsigned char pattern, char *DEVICE_PQ, int freemem);

#define DMA_BLOCKSIZE 66560 * sizeof(unsigned char)
#define MAX_DISKS 255

/* This enables the debug statements */
//#define CUDACOPY


/**
 * Main Function of control
 *
 * @param argc		: # of arguments
 * @param **argv	: Array of arguments
 *
 * @returns			EXIT_FAILURE on error, EXIT_SUCCESS on no error
 */

int main( int argc, char *argv[] )
{
unsigned int freemem;
unsigned int total;
int deviceCount;
int device;
char name[256];
int ret;
int i;
int durations = 1;

char *DEVICE_PQ;
CUdevice 	dev;
struct cudaDeviceProp prop;
cudaError_t result;
	
cuInit(0);
printf("Barracuda CUDA memtest\n");

if(argc > 1){
	durations = atoi(argv[1]);
	if( (durations < 1) || (durations > 20) ){
		printf("Number of durations is to small or higher then 20!!!\n");
		return 1;
		}
	}

cudaGetDeviceCount(&deviceCount);
for (device = 0; device < deviceCount; ++device) {
	cudaSetDevice(device);
	
	cuDeviceGet(&dev, device);
	cuDeviceGetName((char *)&name, 256, dev);
	cudaGetDeviceProperties(&prop, dev);
	
	printf("Getting device memory informations (device %d = %s).\n", device, name );
	
	cuDeviceTotalMem(&total, dev);
	freemem = total;
	
	printf("Total     : %d MB\n", ((total/1024)/1024) );
	
	result = cudaMalloc((void **)&DEVICE_PQ, freemem);
	while( result == cudaErrorMemoryAllocation ){
		freemem = freemem - (1024*1024);
		result = cudaMalloc((void**)&DEVICE_PQ, freemem);
		if(freemem < (1024*1024) ){
			printf("out of memmory!!!\n");
			return 1;
			}
		}

	printf("Free      : %d MB\n", ((freemem/1024)/1024) );
	printf("Durations : %d\n", durations);
	
	#ifdef CUDACOPY
	error_t = cudaGetLastError();
	printf("%s\n", cudaGetErrorString(error_t) );	
	#endif
	
	for(i=0; i<durations; i++){
		ret = gen_pattern("Generating pattern one                  : []", 85, DEVICE_PQ, freemem);
		if(ret == 1){
			return 1;
			}
	
		ret = gen_pattern("Generating pattern two (anti pattern)   : []", 170, DEVICE_PQ, freemem);
		if(ret == 1){
			return 1;
			}

		ret = gen_pattern("Generating pattern three                : []", 255, DEVICE_PQ, freemem);
		if(ret == 1){
			return 1;
			}

		ret = gen_pattern("Generating pattern four (anti pattern)  : []", 0, DEVICE_PQ, freemem);
		if(ret == 1){
			return 1;
			}
		
		}

	cudaFree(DEVICE_PQ);
	
	printf("Test succeeded! -> This is a valid CUDA-device\n");
	}

return 0;
}



/**
 * Generate a pattern, copy to the GPU. After tthat copy the pattern back.
 *
 * @param *output_tag		: Local memory
 * @param pattern			: Bit-Pattern
 * @param *DEVICE_PQ		: Device Pointer
 * @param freemem			: Free card memory
 *
 * @returns			0 on Success, 1 on failure
 */

int gen_pattern(const char *output_tag, unsigned char pattern, char *DEVICE_PQ, int freemem)
{
int i,j;
unsigned char *pattern_pointer;
#ifdef CUDACOPY
	cudaError_t error_t;
	const char *error;
#endif

printf("%s", output_tag);
pattern_pointer = (unsigned char *)malloc(sizeof(unsigned char) * freemem);

if(pattern == 0){
	pattern = 255;
	}

for(j=0; j<30; j++){
	printf("\b#]");
	fflush(stdout);

	memset( pattern_pointer, pattern, freemem);
	cudaMemcpy(DEVICE_PQ, pattern_pointer, freemem, cudaMemcpyHostToDevice);
	cuCtxSynchronize();

#ifdef CUDACOPY
	error_t = cudaGetLastError();
	printf("\n%s\n", cudaGetErrorString(error_t) );
#endif
		
	memset( pattern_pointer, 0, freemem);
	cudaMemcpy(pattern_pointer, DEVICE_PQ, freemem, cudaMemcpyDeviceToHost);

#ifdef CUDACOPY
	error_t = cudaGetLastError();
	printf("\n%s\n", cudaGetErrorString(error_t) );
#endif
	
	for(i = 0; i<freemem; i++){
		if(pattern_pointer[i] != pattern){
			printf("\nbad adress %u\n", i);
			cudaFree(DEVICE_PQ);
			return 1;
			}
		}
	}

printf("\n");
free(pattern_pointer);
return 0;
}
