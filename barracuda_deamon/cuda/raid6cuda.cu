/**
 * \file
 * \brief	Cuda implementation of the raid6 userspace functions
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
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
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>
#include <time.h>
#include <sys/time.h>
#include <math.h>
#include <syslog.h>

#include <cuda_runtime_api.h>
#include <cuda.h>

#include "raid6cuda.h"

#define INHOST_COPY
#define CUDA_COPY
//#define ASYNC
#define KERNEL_EXEC

#define DMA_BLOCKSIZE 524288
#define THREAD_BLOCKSIZE 256

#define NBYTES_CUDA(x) ((x) * 0x0101010101010101UL)

static u8 *DEVICE_DP_1;
static u8 *DEVICE_PQ_1;
	
static u8 *DEVICE_DP_2;
static u8 *DEVICE_PQ_2;

#ifdef ASYNC
	static u8 *HOST_DP_1;
	static u8 *HOST_PQ_1;
	
	static u8 *HOST_DP_2;
	static u8 *HOST_PQ_2;
#endif

static int mem_tag = 0;

// function prototypes
#ifdef ASYNC
static void raid6_cuda_gen_syndrome_asynccopy(int disks, size_t bytes, void **ptrs);
#endif
#ifndef ASYNC
static void raid6_cuda_gen_syndrome_synccopy(int disks, size_t bytes, void **ptrs);
#endif

static void inline get_card_mem(void);

__global__ void syndrome_block( u8 *DEVICE_DP, u8 *DEVICE_PQ, int z0);


/**
 * This is NVIDIA CUDA version of gen_syndrome
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */

extern void raid6_cuda_gen_syndrome(int disks, size_t bytes, void **ptrs)
{	 
#ifdef ASYNC
	raid6_cuda_gen_syndrome_asynccopy(disks, bytes, ptrs);
#endif
	
#ifndef ASYNC
	raid6_cuda_gen_syndrome_synccopy(disks, bytes, ptrs);
#endif
}



/**
 * This is NVIDIA CUDA version of gen_syndrome, which uses asynchronious copy
 * and execution.
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */
#ifdef ASYNC
static void raid6_cuda_gen_syndrome_asynccopy(int disks, size_t bytes, void **ptrs)
{
dim3 dimBlock;
dim3 dimGrid;
	
// variables
int i, j;
static u8 **dptrs = (u8 **)ptrs;

get_card_mem();
	
unsigned long runs = floor(bytes/(DMA_BLOCKSIZE*2));
unsigned long carry_off = 0;

dimBlock.x=THREAD_BLOCKSIZE;
dimBlock.y=1;
dimBlock.z=1;
dimGrid.x=(DMA_BLOCKSIZE/(dimBlock.x*8));
dimGrid.y=1;
	
cudaStream_t stream[2];
	
#ifdef DEBUG_LEVEL_8
	printf("block_x : %d, dimgrid_x : %d, runs : %d\n", dimBlock.x, dimGrid.x, runs);
	cudaError_t error_t;
	error_t = cudaGetLastError();
	printf("stream create : %s\n", cudaGetErrorString(error_t) );
#endif

u8 *tmp;
	
for(j=0; j<runs; j++){
	cudaStreamCreate(&stream[0]);
	cudaStreamCreate(&stream[1]);
	
	// Copy the stuff to the page locked buffer
	for(i=0; i<disks-2; i++){
		#ifdef INHOST_COPY
		tmp = dptrs[i];
		cudaMemcpy(	&HOST_DP_1[i*DMA_BLOCKSIZE], 
					&tmp[(j*2*DMA_BLOCKSIZE)], 
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToHost);

		cudaMemcpy(	&HOST_DP_2[i*DMA_BLOCKSIZE], 
					&tmp[(j*2*DMA_BLOCKSIZE)+DMA_BLOCKSIZE], 
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToHost);
		#endif
		}
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("inhost copy to : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef CUDA_COPY
	cudaMemcpyAsync( DEVICE_DP_1, HOST_DP_1, DMA_BLOCKSIZE*(disks-2), cudaMemcpyHostToDevice, stream[0]);
	cudaMemcpyAsync( DEVICE_DP_2, HOST_DP_2, DMA_BLOCKSIZE*(disks-2), cudaMemcpyHostToDevice, stream[1]);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy to device : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef KERNEL_EXEC
	syndrome_block<<<dimGrid, dimBlock, stream[0]>>>( DEVICE_DP_1, DEVICE_PQ_1, disks-3);
	syndrome_block<<<dimGrid, dimBlock, stream[1]>>>( DEVICE_DP_2, DEVICE_PQ_2, disks-3);
	#endif
	
	#ifndef KERNEL_EXEC
	cudaThreadSynchronize();
	#endif
	
	#ifdef DEBUG_LEVEL_8 
		error_t = cudaGetLastError();
		printf("kernel exec : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef CUDA_COPY
	cudaMemcpyAsync( HOST_PQ_1, DEVICE_PQ_1, DMA_BLOCKSIZE*2, cudaMemcpyDeviceToHost, stream[0]);
	cudaMemcpyAsync( HOST_PQ_2, DEVICE_PQ_2, DMA_BLOCKSIZE*2, cudaMemcpyDeviceToHost, stream[1]);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy from device : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	cudaThreadSynchronize();
	
	#ifdef INHOST_COPY
	cudaMemcpy(&dptrs[disks-1][j*2*DMA_BLOCKSIZE], HOST_PQ_1, DMA_BLOCKSIZE, cudaMemcpyHostToHost);
	cudaMemcpy(&dptrs[disks-2][j*2*DMA_BLOCKSIZE], &HOST_PQ_1[1], DMA_BLOCKSIZE, cudaMemcpyHostToHost);
	
	cudaMemcpy(&dptrs[disks-1][(j*2*DMA_BLOCKSIZE)+DMA_BLOCKSIZE], HOST_PQ_2, DMA_BLOCKSIZE, cudaMemcpyHostToHost);
	cudaMemcpy(&dptrs[disks-2][(j*2*DMA_BLOCKSIZE)+DMA_BLOCKSIZE], &HOST_PQ_2[1], DMA_BLOCKSIZE, cudaMemcpyHostToHost);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy PQ inhost : %s\n", cudaGetErrorString(error_t) );
	#endif
		
	cudaStreamDestroy(stream[0]);
	cudaStreamDestroy(stream[1]);
	}
	
// This is for the part which fits not into a 2*DMA_BLOCKSIZE big block
// but in a DMA_BLOCKSIZE big block
carry_off = bytes-(runs * 2 * DMA_BLOCKSIZE);
if(carry_off >= DMA_BLOCKSIZE){
	cudaStreamCreate(&stream[0]);
	
	// Copy the stuff to the page locked buffer
	for(i=0; i<disks-2; i++){
		#ifdef INHOST_COPY
		tmp = dptrs[i];
		cudaMemcpy(	&HOST_DP_1[i*DMA_BLOCKSIZE], 
					&tmp[(j*2*DMA_BLOCKSIZE)], 
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToHost);
		#endif
		}
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("inhost copy to : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef CUDA_COPY
	cudaMemcpyAsync( DEVICE_DP_1, HOST_DP_1, DMA_BLOCKSIZE*(disks-2), cudaMemcpyHostToDevice, stream[0]);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy to device : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef KERNEL_EXEC
	syndrome_block<<<dimGrid, dimBlock, stream[0]>>>( DEVICE_DP_1, DEVICE_PQ_1, disks-3);
	#endif
	
	#ifndef KERNEL_EXEC
	cudaThreadSynchronize();
	#endif
	
	#ifdef DEBUG_LEVEL_8 
		error_t = cudaGetLastError();
		printf("kernel exec : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef CUDA_COPY
	cudaMemcpyAsync( HOST_PQ_1, DEVICE_PQ_1, DMA_BLOCKSIZE*2, cudaMemcpyDeviceToHost, stream[0]);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy from device : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	cudaThreadSynchronize();
	
	#ifdef INHOST_COPY
	cudaMemcpy(&dptrs[disks-1][j*2*DMA_BLOCKSIZE], HOST_PQ_1, DMA_BLOCKSIZE, cudaMemcpyHostToHost);
	cudaMemcpy(&dptrs[disks-1][(j*2*DMA_BLOCKSIZE)+DMA_BLOCKSIZE], HOST_PQ_2, DMA_BLOCKSIZE, cudaMemcpyHostToHost);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy PQ inhost : %s\n", cudaGetErrorString(error_t) );
	#endif
		
	cudaStreamDestroy(stream[0]);

	j=(j*2)+1;
	carry_off = carry_off-DMA_BLOCKSIZE;
	}
	
	
// This is for the last part which fits not into a DMA_BLOCKSIZE big block.
if(carry_off > 0){
	//-------------------------------------------------------------------
	cudaStreamCreate(&stream[0]);
	
	// Copy the stuff to the page locked buffer
	for(i=0; i<disks-2; i++){
		#ifdef INHOST_COPY
		tmp = dptrs[i];
		cudaMemcpy(	&HOST_DP_1[i*DMA_BLOCKSIZE], 
					&tmp[j*DMA_BLOCKSIZE], 
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToHost);
		#endif
		}
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("inhost copy to : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef CUDA_COPY
	cudaMemcpyAsync( DEVICE_DP_1, HOST_DP_1, DMA_BLOCKSIZE*(disks-2), cudaMemcpyHostToDevice, stream[0]);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy to device : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef KERNEL_EXEC
	dimBlock.x=THREAD_BLOCKSIZE;
	dimBlock.y=1;
	dimBlock.z=1;
	dimGrid.x=(carry_off/(dimBlock.x*8))+1;
	dimGrid.y=1;
	syndrome_block<<<dimGrid, dimBlock, stream[0]>>>( DEVICE_DP_1, DEVICE_PQ_1, disks-3);
	#endif

	#ifndef KERNEL_EXEC
	cudaThreadSynchronize();
	#endif
	
	#ifdef DEBUG_LEVEL_8 
		error_t = cudaGetLastError();
		printf("kernel exec : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef CUDA_COPY
	cudaMemcpyAsync( HOST_PQ_1, DEVICE_PQ_1, DMA_BLOCKSIZE*2, cudaMemcpyDeviceToHost, stream[0]);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy from device : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	cudaThreadSynchronize();
	
	#ifdef INHOST_COPY
	cudaMemcpy(&dptrs[disks-1][j*2*DMA_BLOCKSIZE], HOST_PQ_1, DMA_BLOCKSIZE, cudaMemcpyHostToHost);
	cudaMemcpy(&dptrs[disks-1][(j*2*DMA_BLOCKSIZE)+DMA_BLOCKSIZE], HOST_PQ_2, DMA_BLOCKSIZE, cudaMemcpyHostToHost);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("copy PQ inhost : %s\n", cudaGetErrorString(error_t) );
	#endif
		
	cudaStreamDestroy(stream[0]);
	
	}

}
#endif


/**
 * This is NVIDIA CUDA version of gen_syndrome, which uses synchronious copy and 
 * execution.
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */
#ifndef ASYNC
static void raid6_cuda_gen_syndrome_synccopy(int disks, size_t bytes, void **ptrs)
{
dim3 dimBlock;
dim3 dimGrid;
	
/* variables */
int i, j;
static u8 **dptrs = (u8 **)ptrs;

get_card_mem();
	
unsigned long runs = floor(bytes/(DMA_BLOCKSIZE*2));
unsigned long carry_off = 0;

dimBlock.x=THREAD_BLOCKSIZE;
dimBlock.y=1;
dimBlock.z=1;
dimGrid.x=(DMA_BLOCKSIZE/(dimBlock.x*8));
dimGrid.y=1;
	
#ifdef DEBUG_LEVEL_8
	printf("block_x : %d, dimgrid_x : %d, runs : %d\n", dimBlock.x, dimGrid.x, runs);
	cudaError_t error_t;
#endif

for(j=0; j<runs; j++){	
	#ifdef CUDA_COPY
	for(i=0; i<disks-2; i++){		
		cudaMemcpy( &DEVICE_DP_1[i*DMA_BLOCKSIZE], 
				   	&dptrs[i][j*2*DMA_BLOCKSIZE],
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToDevice);
		
		cudaMemcpy( &DEVICE_DP_2[i*DMA_BLOCKSIZE], 
				   	&dptrs[i][(j*2*DMA_BLOCKSIZE)+DMA_BLOCKSIZE],
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToDevice);
		}
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("todev copy to : %s\n", cudaGetErrorString(error_t) );
	#endif

	#ifdef KERNEL_EXEC
	syndrome_block<<<dimGrid, dimBlock>>>( DEVICE_DP_1, DEVICE_PQ_1, disks-3);
	syndrome_block<<<dimGrid, dimBlock>>>( DEVICE_DP_2, DEVICE_PQ_2, disks-3);
	#endif
	
	cudaThreadSynchronize();
	
	#ifdef DEBUG_LEVEL_8 
		error_t = cudaGetLastError();
		printf("kernel exec : %s\n", cudaGetErrorString(error_t) );
	#endif
		
	#ifdef CUDA_COPY
	cudaMemcpy(&dptrs[disks-2][j*2*DMA_BLOCKSIZE], 
			   DEVICE_PQ_1, DMA_BLOCKSIZE, 
			   cudaMemcpyDeviceToHost);
	cudaMemcpy(&dptrs[disks-1][j*2*DMA_BLOCKSIZE], 
			   &DEVICE_PQ_1[DMA_BLOCKSIZE], DMA_BLOCKSIZE, 
			   cudaMemcpyDeviceToHost);
	
	cudaMemcpy(&dptrs[disks-2][(j*2*DMA_BLOCKSIZE)+DMA_BLOCKSIZE], 
			   DEVICE_PQ_2, DMA_BLOCKSIZE, cudaMemcpyDeviceToHost);
	cudaMemcpy(&dptrs[disks-1][(j*2*DMA_BLOCKSIZE)+DMA_BLOCKSIZE], 
			   &DEVICE_PQ_2[DMA_BLOCKSIZE], DMA_BLOCKSIZE, cudaMemcpyDeviceToHost);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("fromdev copy : %s\n", cudaGetErrorString(error_t) );
	#endif
	}
	
// This is for the part which fits not into a 2*DMA_BLOCKSIZE big block
// but in a DMA_BLOCKSIZE big block
carry_off = bytes-(runs * 2 * DMA_BLOCKSIZE);
if(carry_off >= DMA_BLOCKSIZE){
	#ifdef CUDA_COPY
	for(i=0; i<disks-2; i++){		
		cudaMemcpy( &DEVICE_DP_1[i*DMA_BLOCKSIZE], 
				   	&dptrs[i][j*2*DMA_BLOCKSIZE],
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToDevice);
		}
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("todev copy to : %s\n", cudaGetErrorString(error_t) );
	#endif

	#ifdef KERNEL_EXEC
	syndrome_block<<<dimGrid, dimBlock>>>( DEVICE_DP_1, DEVICE_PQ_1, disks-3);
	#endif
	
	cudaThreadSynchronize();
	
	#ifdef DEBUG_LEVEL_8 
		error_t = cudaGetLastError();
		printf("kernel exec : %s\n", cudaGetErrorString(error_t) );
	#endif
		
	#ifdef CUDA_COPY
	cudaMemcpy(&dptrs[disks-2][j*2*DMA_BLOCKSIZE], 
			   DEVICE_PQ_1, DMA_BLOCKSIZE, 
			   cudaMemcpyDeviceToHost);
	cudaMemcpy(&dptrs[disks-1][j*2*DMA_BLOCKSIZE], 
			   &DEVICE_PQ_1[DMA_BLOCKSIZE], DMA_BLOCKSIZE, 
			   cudaMemcpyDeviceToHost);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("fromdev copy : %s\n", cudaGetErrorString(error_t) );
	#endif
		
	j=(j*2)+1;
	carry_off = carry_off-DMA_BLOCKSIZE;
	}

// This is for the last part which fits not into a DMA_BLOCKSIZE big block.
if(carry_off > 0){
	#ifdef CUDA_COPY
	for(i=0; i<disks-2; i++){		
		cudaMemcpy( &DEVICE_DP_1[i*DMA_BLOCKSIZE], 
				   	&dptrs[i][j*DMA_BLOCKSIZE],
					carry_off, 
					cudaMemcpyHostToDevice);
		}
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("todev copy to : %s\n", cudaGetErrorString(error_t) );
	#endif

	#ifdef KERNEL_EXEC
	dimBlock.x=THREAD_BLOCKSIZE;
	dimBlock.y=1;
	dimBlock.z=1;
	dimGrid.x=(carry_off/(dimBlock.x*8))+1;
	dimGrid.y=1;	
	syndrome_block<<<dimGrid, dimBlock>>>( DEVICE_DP_1, DEVICE_PQ_1, disks-3);
	#endif
	
	cudaThreadSynchronize();
	
	#ifdef DEBUG_LEVEL_8 
		error_t = cudaGetLastError();
		printf("kernel exec : %s\n", cudaGetErrorString(error_t) );
	#endif
		
	#ifdef CUDA_COPY
	cudaMemcpy(&dptrs[disks-2][j*DMA_BLOCKSIZE], 
			   DEVICE_PQ_1, carry_off, 
			   cudaMemcpyDeviceToHost);
	cudaMemcpy(&dptrs[disks-1][j*DMA_BLOCKSIZE], 
			   &DEVICE_PQ_1[DMA_BLOCKSIZE], carry_off, 
			   cudaMemcpyDeviceToHost);
	#endif
	
	#ifdef DEBUG_LEVEL_8
	error_t = cudaGetLastError();
	printf("fromdev copy : %s\n", cudaGetErrorString(error_t) );
	#endif
	}
	
}
#endif



/**
 * In CUDA each iteration of a loop can be expressed as a thread. This function
 * generate the syndrome for one byte vector of each disk. 
 *
 * @param *DEVICE_DP : marshalled data from the discs, which are represented in a linearized array
 * @param *DEVICE_PQ : XOR Parity and RS double parity
 * @param z0         : # of the highest data-disk
 *
 * @returns			void
 */

__global__ void syndrome_block( u8 *DEVICE_DP, u8 *DEVICE_PQ, int z0)
{
/*
int gdx = gridDim.x;
int gdy = gridDim.y;

int bdx = blockDim.x;
int bdy = blockDim.y;
int bdz = blockDim.z;
	
int by = blockIdx.y;
int bz = blockIdx.z;
	
int ty = threadIdx.y;
*/

int bx = blockIdx.x;
int tx = threadIdx.x;
int d  = ((bx*THREAD_BLOCKSIZE)+tx)*8;
	
int z;

__shared__ unsigned long wd0[THREAD_BLOCKSIZE];
__shared__ unsigned long wq0[THREAD_BLOCKSIZE]; 
__shared__ unsigned long wp0[THREAD_BLOCKSIZE]; 
__shared__ unsigned long w10[THREAD_BLOCKSIZE];
__shared__ unsigned long w20[THREAD_BLOCKSIZE];

u8 *p, *q;
p = DEVICE_PQ;
q = &DEVICE_PQ[DMA_BLOCKSIZE];

//for ( d = 0; d < bytes; d += NSIZE ){
wq0[tx] = wp0[tx] = *(unsigned long *)&DEVICE_DP[(z0*DMA_BLOCKSIZE)+d];
for ( z = z0-1; z >= 0; z-- ){
	wd0[tx] = *(unsigned long *)&DEVICE_DP[(z*DMA_BLOCKSIZE)+d];
	wp0[tx] ^= wd0[tx];
	
	//w20 = MASK(wq0);
	wq0[tx] = wq0[tx] & NBYTES_CUDA(0x80);
	wq0[tx] = (wq0[tx] << 1) - (wq0[tx] >> 7);
		
	//w10 = SHLBYTE(wq0);
	w10[tx] = (wq0[tx] << 1) & NBYTES_CUDA(0xfe);
	
	w20[tx] &= NBYTES_CUDA(0x1d);
	w10[tx] ^= w20[tx];
	wq0[tx] = w10[tx] ^ wd0[tx];
	}
	
*(unsigned long *)&p[d] = wp0[tx];
*(unsigned long *)&q[d] = wq0[tx];

//*(unsigned long *)&p[d] = 4;
//*(unsigned long *)&q[d] = 8;

}



static void inline get_card_mem(void)
{
if(mem_tag == 0){
	cudaMalloc((void **)&DEVICE_DP_1, DMA_BLOCKSIZE*256);
	cudaMalloc((void **)&DEVICE_PQ_1, DMA_BLOCKSIZE*2);
	
	cudaMalloc((void **)&DEVICE_DP_2, DMA_BLOCKSIZE*256);
	cudaMalloc((void **)&DEVICE_PQ_2, DMA_BLOCKSIZE*2);

	#ifdef ASYNC
	cudaMallocHost((void **)&HOST_DP_1, DMA_BLOCKSIZE*256);
	cudaMallocHost((void **)&HOST_PQ_1, DMA_BLOCKSIZE*2);
	
	cudaMallocHost((void **)&HOST_DP_2, DMA_BLOCKSIZE*256);
	cudaMallocHost((void **)&HOST_PQ_2, DMA_BLOCKSIZE*2);
	#endif
	
	cudaError_t error_t;
	error_t = cudaGetLastError();
	if( 0 != strcmp(cudaGetErrorString(error_t), "no error") ){
		printf("Device allocation failed!\n");
		exit(1);
		}
	
	#ifdef DEBUG_LEVEL_8 
	printf("getting device memory : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	mem_tag = 1;
	}
}



/**
 * Free the memory from the device
 *
 * @returns			void
 */

extern void release_card_memory(void)
{
cudaFree(DEVICE_DP_1);
cudaFree(DEVICE_PQ_1);
	
cudaFree(DEVICE_DP_2);
cudaFree(DEVICE_PQ_2);
	
#ifdef ASYNC
cudaFree(HOST_DP_1);
cudaFree(HOST_PQ_1);
	
cudaFree(HOST_DP_2);
cudaFree(HOST_PQ_2);
#endif
}

