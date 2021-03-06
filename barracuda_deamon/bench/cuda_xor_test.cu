/**
 * \file
 * \brief	Benchmarking function for the CUDA XOR implementation
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 7.8.2008
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

# include "cuda_xor_test.h"

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

#include "../service.h"

/* DEFINES */
# define BL_SIZE  10000000

#define THREAD_BLOCKSIZE 256

__host__ void tester_xor( unsigned long bl_size);
__host__ void xor_it_cpu( char *A, char *B, char *C, unsigned long bl_size );
__global__ void xor_it_cuda( char *A, char *B, char *C, unsigned long bl_size );



#ifndef MAIN_IS_ACTIVE
int main()
{
	test_cuda_xor_perf();
	return 0;
}
#endif



/**
 * Main routine which tests the XOR function for all defined block sizes. The
 * intervall is defined by the two preprocessors BL_SIZE_START and BL_SIZE_STOP
 *
 *
 * @returns			void
 */

__host__ void test_cuda_xor_perf()
{
	unsigned long i = 0;
	for(i=0; i<=30; i++){
		tester_xor(BL_SIZE);
		}
}



/**
 * This function tests XORing for CUDA with synchronious copys,
 * CUDA with asynchronious copys and on the CPU for a defined DMA
 * blocksize and prints the results as CSV (comma separated values)
 * on the screen.
 *
 * @param bl_size	: Blocksize of each data transfer
 *
 * @returns		void
 */

__host__ void tester_xor( unsigned long bl_size)
{
	double time_all = 0;
	double time_one = 0;
	unsigned long runs = 0;

	/* get Memory on the device */
	char *DEVICE_A;
	char *DEVICE_B;
	char *DEVICE_C;
	cudaMalloc((void**)&DEVICE_A, bl_size);
	cudaMalloc((void**)&DEVICE_B, bl_size);
	cudaMalloc((void**)&DEVICE_C, bl_size);
	
	char *A = (char *)malloc(bl_size);
	char *B = (char *)malloc(bl_size);
	char *C = (char *)malloc(bl_size);
	
	/* define thread grid dimension */
	dim3 dimBlock;
	dim3 dimGrid;
	
	dimBlock.x=THREAD_BLOCKSIZE;
	dimBlock.y=1;
	dimBlock.z=1;
	dimGrid.x=(bl_size/(dimBlock.x*8));
	dimGrid.y=1;
	
	/*----reset-vars---------------------------------*/
	runs            = 0;
	time_one		= 0;
	time_all        = 0;
	
	/*----test-gpu-performance-----------------------*/
	
	while(time_all < 1){
		runs++;
		time_one = gtd_second();

		xor_it_cuda<<<dimGrid, dimBlock>>>(DEVICE_A, DEVICE_B, DEVICE_C, bl_size);

		time_all = time_all + (gtd_second() - time_one);
		}
	printf("GPU ; %f\n", ((runs*bl_size)/time_all) );
	
	/*
	cudaError_t error_t;
	error_t = cudaGetLastError();
	printf("kernel : %s\n", cudaGetErrorString(error_t) );
	*/
	
	/*----reset-vars---------------------------------*/
	runs            = 0;
	time_one		= 0;
	time_all        = 0;

	/*----test-cpu-performance----------------------*/	
	while(time_all < 1){
		runs++;
		time_one = gtd_second();
			xor_it_cpu(A, B, C, bl_size);
		time_all = time_all + (gtd_second() - time_one);
		}
	printf("CPU ; %f\n", ((runs*bl_size)/time_all) );

	/*------------------------------------------------------------------------*/

	/* Free memory */
	cudaFree(DEVICE_A);
	cudaFree(DEVICE_B);
	cudaFree(DEVICE_C);
	free(A);
	free(B);
	free(C);
}



/**
 * XOR compute kernel for the main CPU
 *
 * @param *A			: A is an array of bytes for the input
 * @param *B			: B is an array of bytes for the input
 * @param *C			: C is an array of bytes for the output
 * @param bl_size		: # of bytes that should be XORd
 *
 * @returns		void
 */

__host__ void xor_it_cpu( char *A, char *B, char *C, unsigned long bl_size )
{
unsigned long i = 0;	
unsigned long *TMP_A = (unsigned long *)A;
unsigned long *TMP_B = (unsigned long *)B;
unsigned long *TMP_C = (unsigned long *)C;
	
for(i=0; i < (bl_size/sizeof(unsigned long)); i++){
	TMP_C[i] = TMP_A[i] ^ TMP_B[i];
	}
	
}



/**
 * XOR compute kernel for the main GPU
 *
 * @param *A			: A is an array of bytes for the input
 * @param *B			: B is an array of bytes for the input
 * @param *C			: C is an array of bytes for the output
 * @param bl_size		: number of bytes
 *
 * @returns		void
 */

__global__ void xor_it_cuda( char *A, char *B, char *C, unsigned long bl_size )
{
	int bx = blockIdx.x;
	int tx = threadIdx.x;
	int d  = (bx*THREAD_BLOCKSIZE)+tx;
	
	unsigned long *tmp_a, *tmp_b, *tmp_c;
	
	tmp_a = (unsigned long *)A;
	tmp_b = (unsigned long *)B;
	tmp_c = (unsigned long *)C;
	
	__shared__ unsigned long a_stream[8];
	__shared__ unsigned long b_stream[8];
	__shared__ unsigned long c_stream[8];
	
	c_stream[tx] = tmp_c[d];
	b_stream[tx] = tmp_b[d];
	a_stream[tx]  = c_stream[tx] ^ b_stream[tx];
	tmp_a[d]     = a_stream[tx];
	
}
