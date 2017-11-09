/**
 * \file
 * \brief	Multi error correcting rs-encoder prototype
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: ALPHA \n
 * Date of creation : 16.12.2008
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
#include <stdlib.h>
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

//#define GEN
#define DISKS 9
#define CHECK_SYMBOLS 3
//#define BYTES 4096
#define BYTES 524288
//#define BYTES 4128


#define NW (1 << w)
//#define DEBUG_MULT_RS
#define CUDA_COPY
#define KERNEL_EXEC

//#define DMA_BLOCKSIZE 4096
//#define THREAD_BLOCKSIZE 64

#define DMA_BLOCKSIZE 524288
#define THREAD_BLOCKSIZE 256

//#define DMA_BLOCKSIZE 256
//#define THREAD_BLOCKSIZE 16


extern void multi_rs_cuda_gen_syndrome(int disks, size_t bytes, void **ptrs);

extern void multi_rs_soft_gen_syndrome(int disks, size_t bytes, void **ptrs);
inline unsigned char mult_gf(unsigned char a, unsigned char b);

__global__ void rs_kernel( unsigned char *DEVICE_DP, unsigned char *DEVICE_PQ, int disks);
__device__ inline unsigned char mult_gf_shader(unsigned char a, unsigned char b, unsigned char gflog[], unsigned char gfilog[]);
static void inline get_card_mem(void);

int setup_tables(void);
double gtd_second(void);

static unsigned char gflog[] = {
0, 0, 1, 25, 2, 50, 26, 198, 3, 223, 51, 238, 27, 104, 199, 75, 4, 100, 224, 14,
52, 141, 239, 129, 28, 193, 105, 248, 200, 8, 76, 113, 5, 138, 101, 47, 225, 36,
15, 33, 53, 147, 142, 218, 240, 18, 130, 69, 29, 181, 194, 125, 106, 39, 249, 185,
201, 154, 9, 120, 77, 228, 114, 166, 6, 191, 139, 98, 102, 221, 48, 253, 226, 152,
37, 179, 16, 145, 34, 136, 54, 208, 148, 206, 143, 150, 219, 189, 241, 210, 19,
92, 131, 56, 70, 64, 30, 66, 182, 163, 195, 72, 126, 110, 107, 58, 40, 84, 250,
133, 186, 61, 202, 94, 155, 159, 10, 21, 121, 43, 78, 212, 229, 172, 115, 243, 167,
87, 7, 112, 192, 247, 140, 128, 99, 13, 103, 74, 222, 237, 49, 197, 254, 24, 227,
165, 153, 119, 38, 184, 180, 124, 17, 68, 146, 217, 35, 32, 137, 46, 55, 63, 209,
91, 149, 188, 207, 205, 144, 135, 151, 178, 220, 252, 190, 97, 242, 86, 211, 171,
20, 42, 93, 158, 132, 60, 57, 83, 71, 109, 65, 162, 31, 45, 67, 216, 183, 123, 164,
118, 196, 23, 73, 236, 127, 12, 111, 246, 108, 161, 59, 82, 41, 157, 85, 170, 251,
96, 134, 177, 187, 204, 62, 90, 203, 89, 95, 176, 156, 169, 160, 81, 11, 245, 22,
235, 122, 117, 44, 215, 79, 174, 213, 233, 230, 231, 173, 232, 116, 214, 244, 234,
168, 80, 88};

static unsigned char gfilog[] = {
1, 2, 4, 8, 16, 32, 64, 128, 29, 58, 116, 232, 205, 135, 19, 38, 76, 152, 45, 90,
180, 117, 234, 201, 143, 3, 6, 12, 24, 48, 96, 192, 157, 39, 78, 156, 37, 74, 148,
53, 106, 212, 181, 119, 238, 193, 159, 35, 70, 140, 5, 10, 20, 40, 80, 160, 93,
186, 105, 210, 185, 111, 222, 161, 95, 190, 97, 194, 153, 47, 94, 188, 101, 202,
137, 15, 30, 60, 120, 240, 253, 231, 211, 187, 107, 214, 177, 127, 254, 225, 223,
163, 91, 182, 113, 226, 217, 175, 67, 134, 17, 34, 68, 136, 13, 26, 52, 104, 208,
189, 103, 206, 129, 31, 62, 124, 248, 237, 199, 147, 59, 118, 236, 197, 151, 51,
102, 204, 133, 23, 46, 92, 184, 109, 218, 169, 79, 158, 33, 66, 132, 21, 42, 84,
168, 77, 154, 41, 82, 164, 85, 170, 73, 146, 57, 114, 228, 213, 183, 115, 230, 209,
191, 99, 198, 145, 63, 126, 252, 229, 215, 179, 123, 246, 241, 255, 227, 219, 171,
75, 150, 49, 98, 196, 149, 55, 110, 220, 165, 87, 174, 65, 130, 25, 50, 100, 200,
141, 7, 14, 28, 56, 112, 224, 221, 167, 83, 166, 81, 162, 89, 178, 121, 242, 249,
239, 195, 155, 43, 86, 172, 69, 138, 9, 18, 36, 72, 144, 61, 122, 244, 245, 247,
243, 251, 235, 203, 139, 11, 22, 44, 88, 176, 125, 250, 233, 207, 131, 27, 54,
108, 216, 173, 71, 142
};

unsigned short *gflog2, *gfilog2;


/**
 * Main function of control
 *
 * @returns			int
 */

int main()
{
#ifdef GEN
setup_tables();
#endif

#ifndef GEN
int i,j ;
void **dptrs;
unsigned char* tmp;
	
dptrs=(void **)malloc( DISKS*sizeof(void *) );
for(i=0; i < DISKS; i++){
	dptrs[i] = malloc(BYTES);
	}
	
for ( i=0 ; i < DISKS ; i++ ){
	memset(dptrs[i], i, BYTES);
	tmp = (unsigned char *)dptrs[i];
	for ( j=0 ; j < BYTES ; j++ ){
		//printf("%u ", tmp[j]);
		}
	//printf("\n\n");
	}
	
printf("____\n");

//______________________________________________________________________________

double timer, tmp_timer;
	
timer = 0; j = 0;
while(timer < 2){
	tmp_timer = gtd_second();
		multi_rs_soft_gen_syndrome(DISKS, BYTES, dptrs);
	tmp_timer = gtd_second() - tmp_timer;
	timer = timer + tmp_timer;
	j++;
	}
printf("%d ; %u\n", 1, (unsigned long)((BYTES*j)/timer) );
	
timer = 0; j = 0;
while(timer < 2){
	tmp_timer = gtd_second();
		multi_rs_cuda_gen_syndrome(DISKS, BYTES, dptrs);
	tmp_timer = gtd_second() - tmp_timer;
	timer = timer + tmp_timer;
	j++;
	}
printf("%d ; %u\n", 2, (unsigned long)((BYTES*j)/timer) );
	
//multi_rs_soft_gen_syndrome(DISKS, BYTES, dptrs);
//multi_rs_cuda_gen_syndrome(DISKS, BYTES, dptrs);

//______________________________________________________________________________
	
for ( i=0 ; i < DISKS ; i++ ){
	tmp = (unsigned char *)dptrs[i];
	for ( j=0 ; j < BYTES ; j++ ){
		//printf("%u ", tmp[j]);
		}
	//printf("\n\n");
	}

for(i = 0; i < DISKS; i++){
	free(dptrs[i]);
	}
free(dptrs);
#endif
	
return 0;
}

//______________________________________________________________________________

/**
 * This is a multi failure correcting version of gen_syndrome which runs entirely
 * on the cpu.
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */

extern void multi_rs_soft_gen_syndrome(int disks, size_t bytes, void **ptrs)
{
unsigned char matrix_pos_y;
unsigned char matrix_pos_x;
#ifdef DEBUG_MULT_RS
unsigned char tmp;
#endif
	
unsigned char **dptrs = (unsigned char **)ptrs;
	
int i;
int j;
int d;
	
int high_disk = (disks-CHECK_SYMBOLS);
	
for(i=0; i<bytes; i++){
	matrix_pos_y = 0;
	#ifdef DEBUG_MULT_RS
	printf("byte %d\n", i);
	#endif
	
	for(j=high_disk; j<disks; j++){
		matrix_pos_y++;
		matrix_pos_x = matrix_pos_y;
		#ifdef DEBUG_MULT_RS
		printf("%u", matrix_pos_y);
		#endif
		
		dptrs[j][i] = 0;
		for(d=0; d<high_disk; d++){
			dptrs[j][i] ^= mult_gf(matrix_pos_x, dptrs[d][i]);
			#ifdef DEBUG_MULT_RS
			tmp = mult_gf(matrix_pos_x, dptrs[d][i]);
			printf("[(%u*%u) = %u] +", matrix_pos_x, dptrs[d][i], tmp);
			#endif
			matrix_pos_x  = mult_gf(matrix_pos_x, matrix_pos_y);
			}
		#ifdef DEBUG_MULT_RS
		printf("\b = %u\n", dptrs[j][i]);
		#endif
		}
	#ifdef DEBUG_MULT_RS
	printf("\n");
	#endif
	}
}



/**
 * This function implements multiplication on an GF(2) with lookup tables
 *
 * @param a		: first operand
 * @param b		: second operand
 *
 * @returns			result of the GF(2) multiplication
 */

inline unsigned char mult_gf(unsigned char a, unsigned char b)
{
unsigned char sum_log;
int w = 8;
	
if(a==0 || b==0){return 0;}
	
sum_log = gflog[a] + gflog[b];
  
if(sum_log >= NW-1){sum_log -= NW-1;}
 
return gfilog[sum_log];
}

//______________________________________________________________________________

static unsigned char *DEVICE_DP;
static unsigned char *DEVICE_CS;
static int mem_tag = 0;



/**
 * This is a multi failure correcting version of gen_syndrome which runs entirely
 * on the gpu. This function is the body which uploads and executes the compute
 * kernel.
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */

extern void multi_rs_cuda_gen_syndrome(int disks, size_t bytes, void **ptrs)
{
int i, j;
dim3 dimBlock;
dim3 dimGrid;
	
unsigned char **dptrs = (unsigned char **)ptrs;
unsigned long runs  = floor(bytes/DMA_BLOCKSIZE);
unsigned long carry = bytes - (runs * DMA_BLOCKSIZE);
	
get_card_mem();
	
#ifdef DEBUG_MULT_RS
printf("block_x : %d, dimgrid_x : %d, runs : %d\n", dimBlock.x, dimGrid.x, runs);
cudaError_t error_t;
error_t = cudaGetLastError();
printf("cuda_copy : %s\n", cudaGetErrorString(error_t) );
#endif

dimBlock.x=THREAD_BLOCKSIZE;
dimBlock.y=1;
dimBlock.z=1;
dimGrid.x=(DMA_BLOCKSIZE/(dimBlock.x*8));
dimGrid.y=1;
		
for(j=0; j<runs; j++){	
	#ifdef CUDA_COPY
	for(i=0; i<disks-CHECK_SYMBOLS; i++){		
		cudaMemcpy( &DEVICE_DP[i*DMA_BLOCKSIZE], 
				   	&dptrs[i][j*DMA_BLOCKSIZE],
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToDevice);
		}
	#endif
	
	#ifdef KERNEL_EXEC
	rs_kernel<<<dimGrid, dimBlock>>>( DEVICE_DP, DEVICE_CS, disks);
	#endif
	
	#ifdef DEBUG_MULT_RS
		error_t = cudaGetLastError();
		printf("kernel exec : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef CUDA_COPY
	for(i=0; i<CHECK_SYMBOLS; i++){		
		cudaMemcpy( &dptrs[(disks-CHECK_SYMBOLS)+i][j*DMA_BLOCKSIZE],
				    &DEVICE_CS[i*DMA_BLOCKSIZE],
					DMA_BLOCKSIZE, 
					cudaMemcpyDeviceToHost);
		}
	#endif
	
	#ifdef DEBUG_MULT_RS
		error_t = cudaGetLastError();
		printf("cuda_copy_back : %s\n", cudaGetErrorString(error_t) );
	#endif
	}
	
dimBlock.x=THREAD_BLOCKSIZE;
dimBlock.y=1;
dimBlock.z=1;
dimGrid.x=ceil(carry/(dimBlock.x*8));
dimGrid.y=1;
	
if(carry > 0){
	#ifdef CUDA_COPY
	for(i=0; i<disks-CHECK_SYMBOLS; i++){		
		cudaMemcpy( &DEVICE_DP[i*DMA_BLOCKSIZE], 
				   	&dptrs[i][j*carry],
					DMA_BLOCKSIZE, 
					cudaMemcpyHostToDevice);
		}
	#endif
	
	#ifdef KERNEL_EXEC
	rs_kernel<<<dimGrid, dimBlock>>>( DEVICE_DP, DEVICE_CS, disks);
	#endif
	
	#ifdef DEBUG_MULT_RS
		error_t = cudaGetLastError();
		printf("kernel exec : %s\n", cudaGetErrorString(error_t) );
	#endif
	
	#ifdef CUDA_COPY
	for(i=0; i<CHECK_SYMBOLS; i++){		
		cudaMemcpy( &dptrs[(disks-CHECK_SYMBOLS)+i][j*carry],
				    &DEVICE_CS[i*DMA_BLOCKSIZE],
					DMA_BLOCKSIZE, 
					cudaMemcpyDeviceToHost);
		}
	#endif
	
	#ifdef DEBUG_MULT_RS
		error_t = cudaGetLastError();
		printf("cuda_copy_back : %s\n", cudaGetErrorString(error_t) );
	#endif
	}

}


/**
 * This is the rs kernel function.
 *
 * @param *DEVICE_DP : linearized datapointer
 * @param *DEVICE_PQ : linearized checksum pointer
 * @param disks		 : number of drives
 *
 * @returns			void
 */

__global__ void rs_kernel( unsigned char *DEVICE_DP, unsigned char *DEVICE_PQ, int disks)
{
int bx = blockIdx.x;
int tx = threadIdx.x;
int th = ((bx*THREAD_BLOCKSIZE)+tx);

// logarithm
__shared__ unsigned char k_gflog[256];
__shared__ unsigned char k_gfilog[256];

if(tx == 0){
k_gflog[0] = 0;     k_gflog[1] = 0;     k_gflog[2] = 1;     k_gflog[3] = 25;    
k_gflog[4] = 2;     k_gflog[5] = 50;    k_gflog[6] = 26;    k_gflog[7] = 198;   
k_gflog[8] = 3;     k_gflog[9] = 223;   k_gflog[10] = 51;   k_gflog[11] = 238;  
k_gflog[12] = 27;   k_gflog[13] = 104;  k_gflog[14] = 199;  k_gflog[15] = 75;   
k_gflog[16] = 4;    k_gflog[17] = 100;  k_gflog[18] = 224;  k_gflog[19] = 14;
k_gflog[20] = 52;   k_gflog[21] = 141;  k_gflog[22] = 239;  k_gflog[23] = 129;  
k_gflog[24] = 28;   k_gflog[25] = 193;  k_gflog[26] = 105;  k_gflog[27] = 248;  
k_gflog[28] = 200;  k_gflog[29] = 8;    k_gflog[30] = 76;   k_gflog[31] = 113;
	
// inverse logarithm
k_gfilog[0] = 1;    k_gfilog[1] = 2;    k_gfilog[2] = 4;    k_gfilog[3] = 8;
k_gfilog[4] = 16;   k_gfilog[5] = 32;   k_gfilog[6] = 64;   k_gfilog[7] = 128;  
k_gfilog[8] = 29;   k_gfilog[9] = 58;   k_gfilog[10] = 116; k_gfilog[11] = 232; 
k_gfilog[12] = 205; k_gfilog[13] = 135; k_gfilog[14] = 19;  k_gfilog[15] = 38;  
k_gfilog[16] = 76;  k_gfilog[17] = 152; k_gfilog[18] = 45;  k_gfilog[19] = 90;
k_gfilog[20] = 180; k_gfilog[21] = 117; k_gfilog[22] = 234; k_gfilog[23] = 201;
k_gfilog[24] = 143; k_gfilog[25] = 3;   k_gfilog[26] = 6;   k_gfilog[27] = 12;  
k_gfilog[28] = 24;  k_gfilog[29] = 48;  k_gfilog[30] = 96;  k_gfilog[31] = 192; 
}

if(tx == 1){
k_gflog[32] = 5;    k_gflog[33] = 138;  k_gflog[34] = 101;  k_gflog[35] = 47;   
k_gflog[36] = 225;  k_gflog[37] = 36;   k_gflog[38] = 15;   k_gflog[39] = 33;
k_gflog[40] = 53;   k_gflog[41] = 147;  k_gflog[42] = 142;  k_gflog[43] = 218;  
k_gflog[44] = 240;  k_gflog[45] = 18;   k_gflog[46] = 130;  k_gflog[47] = 69;
k_gflog[48] = 29;   k_gflog[49] = 181;  k_gflog[50] = 194;  k_gflog[51] = 125;  
k_gflog[52] = 106;  k_gflog[53] = 39;   k_gflog[54] = 249;  k_gflog[55] = 185;  
k_gflog[56] = 201;  k_gflog[57] = 154;  k_gflog[58] = 9;    k_gflog[59] = 120;
k_gflog[60] = 77;   k_gflog[61] = 228;  k_gflog[62] = 114;  k_gflog[63] = 166;
	
// inverse logarithm
k_gfilog[32] = 157; k_gfilog[33] = 39;  k_gfilog[34] = 78;  k_gfilog[35] = 156; 
k_gfilog[36] = 37;  k_gfilog[37] = 74;  k_gfilog[38] = 148; k_gfilog[39] = 53;
k_gfilog[40] = 106; k_gfilog[41] = 212; k_gfilog[42] = 181; k_gfilog[43] = 119; 
k_gfilog[44] = 238; k_gfilog[45] = 193; k_gfilog[46] = 159; k_gfilog[47] = 35;  
k_gfilog[48] = 70;  k_gfilog[49] = 140; k_gfilog[50] = 5;   k_gfilog[51] = 10;  
k_gfilog[52] = 20;  k_gfilog[53] = 40;  k_gfilog[54] = 80;  k_gfilog[55] = 160; 
k_gfilog[56] = 93;  k_gfilog[57] = 186; k_gfilog[58] = 105; k_gfilog[59] = 210;
k_gfilog[60] = 185; k_gfilog[61] = 111; k_gfilog[62] = 222; k_gfilog[63] = 161;
}

if(tx == 2){
k_gflog[64] = 6;    k_gflog[65] = 191;  k_gflog[66] = 139;  k_gflog[67] = 98;   
k_gflog[68] = 102;  k_gflog[69] = 221;  k_gflog[70] = 48;   k_gflog[71] = 253;  
k_gflog[72] = 226;  k_gflog[73] = 152;  k_gflog[74] = 37;   k_gflog[75] = 179;  
k_gflog[76] = 16;   k_gflog[77] = 145;  k_gflog[78] = 34;   k_gflog[79] = 136;
k_gflog[80] = 54;   k_gflog[81] = 208;  k_gflog[82] = 148;  k_gflog[83] = 206;  
k_gflog[84] = 143;  k_gflog[85] = 150;  k_gflog[86] = 219;  k_gflog[87] = 189;
k_gflog[88] = 241;  k_gflog[89] = 210;  k_gflog[90] = 19;   k_gflog[91] = 92;
k_gflog[92] = 131;  k_gflog[93] = 56;   k_gflog[94] = 70;   k_gflog[95] = 64;

// inverse logarithm
k_gfilog[64] = 95;  k_gfilog[65] = 190; k_gfilog[66] = 97;  k_gfilog[67] = 194;
k_gfilog[68] = 153; k_gfilog[69] = 47;  k_gfilog[70] = 94;  k_gfilog[71] = 188; 
k_gfilog[72] = 101; k_gfilog[73] = 202; k_gfilog[74] = 137; k_gfilog[75] = 15;
k_gfilog[76] = 30;  k_gfilog[77] = 60;  k_gfilog[78] = 120; k_gfilog[79] = 240;
k_gfilog[80] = 253; k_gfilog[81] = 231; k_gfilog[82] = 211; k_gfilog[83] = 187; 
k_gfilog[84] = 107; k_gfilog[85] = 214; k_gfilog[86] = 177; k_gfilog[87] = 127; 
k_gfilog[88] = 254; k_gfilog[89] = 225; k_gfilog[90] = 223; k_gfilog[91] = 163; 
k_gfilog[92] = 91;  k_gfilog[93] = 182; k_gfilog[94] = 113; k_gfilog[95] = 226;
}

if(tx == 3){
k_gflog[96] = 30;   k_gflog[97] = 66;   k_gflog[98] = 182;  k_gflog[99] = 163;
k_gflog[100] = 195; k_gflog[101] = 72;  k_gflog[102] = 126; k_gflog[103] = 110; 
k_gflog[104] = 107; k_gflog[105] = 58;  k_gflog[106] = 40;  k_gflog[107] = 84;  
k_gflog[108] = 250; k_gflog[109] = 133; k_gflog[110] = 186; k_gflog[111] = 61;  
k_gflog[112] = 202; k_gflog[113] = 94;  k_gflog[114] = 155; k_gflog[115] = 159; 
k_gflog[116] = 10;  k_gflog[117] = 21;  k_gflog[118] = 121; k_gflog[119] = 43;
k_gflog[120] = 78;  k_gflog[121] = 212; k_gflog[122] = 229; k_gflog[123] = 172;
k_gflog[124] = 115; k_gflog[125] = 243; k_gflog[126] = 167; k_gflog[127] = 87;

// inverse logarithm
k_gfilog[96] = 217; k_gfilog[97] = 175; k_gfilog[98] = 67;  k_gfilog[99] = 134;
k_gfilog[100] = 17; k_gfilog[101] = 34; k_gfilog[102] = 68; k_gfilog[103] = 136;
k_gfilog[104] = 13; k_gfilog[105] = 26; k_gfilog[106] = 52; k_gfilog[107] = 104;
k_gfilog[108] = 208;k_gfilog[109] = 189;k_gfilog[110] = 103;k_gfilog[111] = 206;
k_gfilog[112] = 129;k_gfilog[113] = 31; k_gfilog[114] = 62; k_gfilog[115] = 124;
k_gfilog[116] = 248;k_gfilog[117] = 237;k_gfilog[118] = 199;k_gfilog[119] = 147;
k_gfilog[120] = 59; k_gfilog[121] = 118;k_gfilog[122] = 236;k_gfilog[123] = 197;
k_gfilog[124] = 151;k_gfilog[125] = 51; k_gfilog[126] = 102;k_gfilog[127] = 204;
}

if(tx == 4){
k_gflog[128] = 7;   k_gflog[129] = 112; k_gflog[130] = 192; k_gflog[131] = 247;
k_gflog[132] = 140; k_gflog[133] = 128; k_gflog[134] = 99;  k_gflog[135] = 13;  
k_gflog[136] = 103; k_gflog[137] = 74;  k_gflog[138] = 222; k_gflog[139] = 237; 
k_gflog[140] = 49;  k_gflog[141] = 197; k_gflog[142] = 254; k_gflog[143] = 24;  
k_gflog[144] = 227; k_gflog[145] = 165; k_gflog[146] = 153; k_gflog[147] = 119; 
k_gflog[148] = 38;  k_gflog[149] = 184; k_gflog[150] = 180; k_gflog[151] = 124; 
k_gflog[152] = 17;  k_gflog[153] = 68;  k_gflog[154] = 146; k_gflog[155] = 217; 
k_gflog[156] = 35;  k_gflog[157] = 32;  k_gflog[158] = 137; k_gflog[159] = 46;

// inverse logarithm
k_gfilog[128] = 133;k_gfilog[129] = 23; k_gfilog[130] = 46; k_gfilog[131] = 92; 
k_gfilog[132] = 184;k_gfilog[133] = 109;k_gfilog[134] = 218;k_gfilog[135] = 169;
k_gfilog[136] = 79; k_gfilog[137] = 158;k_gfilog[138] = 33; k_gfilog[139] = 66;
k_gfilog[140] = 132;k_gfilog[141] = 21; k_gfilog[142] = 42; k_gfilog[143] = 84;
k_gfilog[144] = 168;k_gfilog[145] = 77; k_gfilog[146] = 154;k_gfilog[147] = 41; 
k_gfilog[148] = 82; k_gfilog[149] = 164;k_gfilog[150] = 85; k_gfilog[151] = 170;
k_gfilog[152] = 73; k_gfilog[153] = 146;k_gfilog[154] = 57; k_gfilog[155] = 114;
k_gfilog[156] = 228;k_gfilog[157] = 213;k_gfilog[158] = 183;k_gfilog[159] = 115;
}

if(tx == 5){
k_gflog[160] = 55;  k_gflog[161] = 63;  k_gflog[162] = 209; k_gflog[163] = 91;  
k_gflog[164] = 149; k_gflog[165] = 188; k_gflog[166] = 207; k_gflog[167] = 205; 
k_gflog[168] = 144; k_gflog[169] = 135; k_gflog[170] = 151; k_gflog[171] = 178; 
k_gflog[172] = 220; k_gflog[173] = 252; k_gflog[174] = 190; k_gflog[175] = 97;  
k_gflog[176] = 242; k_gflog[177] = 86;  k_gflog[178] = 211; k_gflog[179] = 171;
k_gflog[180] = 20;  k_gflog[181] = 42;  k_gflog[182] = 93;  k_gflog[183] = 158;
k_gflog[184] = 132; k_gflog[185] = 60;  k_gflog[186] = 57;  k_gflog[187] = 83;  
k_gflog[188] = 71;  k_gflog[189] = 109; k_gflog[190] = 65;  k_gflog[191] = 162; 

// inverse logarithm
k_gfilog[160] = 230;k_gfilog[161] = 209;k_gfilog[162] = 191;k_gfilog[163] = 99; 
k_gfilog[164] = 198;k_gfilog[165] = 145;k_gfilog[166] = 63; k_gfilog[167] = 126;
k_gfilog[168] = 252;k_gfilog[169] = 229;k_gfilog[170] = 215;k_gfilog[171] = 179;
k_gfilog[172] = 123;k_gfilog[173] = 246;k_gfilog[174] = 241;k_gfilog[175] = 255;
k_gfilog[176] = 227;k_gfilog[177] = 219;k_gfilog[178] = 171;k_gfilog[179] = 75;
k_gfilog[180] = 150;k_gfilog[181] = 49; k_gfilog[182] = 98; k_gfilog[183] = 196;
k_gfilog[184] = 149;k_gfilog[185] = 55; k_gfilog[186] = 110;k_gfilog[187] = 220;
k_gfilog[188] = 165;k_gfilog[189] = 87; k_gfilog[190] = 174;k_gfilog[191] = 65; 
}

if(tx == 6){
k_gflog[192] = 31;  k_gflog[193] = 45;  k_gflog[194] = 67;  k_gflog[195] = 216; 
k_gflog[196] = 183; k_gflog[197] = 123; k_gflog[198] = 164; k_gflog[199] = 118;
k_gflog[200] = 196; k_gflog[201] = 23;  k_gflog[202] = 73;  k_gflog[203] = 236;
k_gflog[204] = 127; k_gflog[205] = 12;  k_gflog[206] = 111; k_gflog[207] = 246; 
k_gflog[208] = 108; k_gflog[209] = 161; k_gflog[210] = 59;  k_gflog[211] = 82;  
k_gflog[212] = 41;  k_gflog[213] = 157; k_gflog[214] = 85;  k_gflog[215] = 170; 
k_gflog[216] = 251; k_gflog[217] = 96;  k_gflog[218] = 134; k_gflog[219] = 177;
k_gflog[220] = 187; k_gflog[221] = 204; k_gflog[222] = 62;  k_gflog[223] = 90;  

// inverse logarithm
k_gfilog[192] = 130;k_gfilog[193] = 25; k_gfilog[194] = 50; k_gfilog[195] = 100;
k_gfilog[196] = 200;k_gfilog[197] = 141;k_gfilog[198] = 7;  k_gfilog[199] = 14;
k_gfilog[200] = 28; k_gfilog[201] = 56; k_gfilog[202] = 112;k_gfilog[203] = 224;
k_gfilog[204] = 221;k_gfilog[205] = 167;k_gfilog[206] = 83; k_gfilog[207] = 166;
k_gfilog[208] = 81; k_gfilog[209] = 162;k_gfilog[210] = 89; k_gfilog[211] = 178;
k_gfilog[212] = 121;k_gfilog[213] = 242;k_gfilog[214] = 249;k_gfilog[215] = 239;
k_gfilog[216] = 195;k_gfilog[217] = 155;k_gfilog[218] = 43; k_gfilog[219] = 86;
k_gfilog[220] = 172;k_gfilog[221] = 69; k_gfilog[222] = 138;k_gfilog[223] = 9;  
}
	
if(tx == 7){
k_gflog[224] = 203; k_gflog[225] = 89;  k_gflog[226] = 95;  k_gflog[227] = 176; 
k_gflog[228] = 156; k_gflog[229] = 169; k_gflog[230] = 160; k_gflog[231] = 81;  
k_gflog[232] = 11;  k_gflog[233] = 245; k_gflog[234] = 22;  k_gflog[235] = 235; 
k_gflog[236] = 122; k_gflog[237] = 117; k_gflog[238] = 44;  k_gflog[239] = 215;
k_gflog[240] = 79;  k_gflog[241] = 174; k_gflog[242] = 213; k_gflog[243] = 233; 
k_gflog[244] = 230; k_gflog[245] = 231; k_gflog[246] = 173; k_gflog[247] = 232; 
k_gflog[248] = 116; k_gflog[249] = 214; k_gflog[250] = 244; k_gflog[251] = 234; 
k_gflog[252] = 168; k_gflog[253] = 80;  k_gflog[254] = 88;

// inverse logarithm
k_gfilog[224] = 18; k_gfilog[225] = 36; k_gfilog[226] = 72; k_gfilog[227] = 144;
k_gfilog[228] = 61; k_gfilog[229] = 122;k_gfilog[230] = 244;k_gfilog[231] = 245;
k_gfilog[232] = 247;k_gfilog[233] = 243;k_gfilog[234] = 251;k_gfilog[235] = 235;
k_gfilog[236] = 203;k_gfilog[237] = 139;k_gfilog[238] = 11; k_gfilog[239] = 22;
k_gfilog[240] = 44; k_gfilog[241] = 88; k_gfilog[242] = 176;k_gfilog[243] = 125;
k_gfilog[244] = 250;k_gfilog[245] = 233;k_gfilog[246] = 207;k_gfilog[247] = 131;
k_gfilog[248] = 27; k_gfilog[249] = 54; k_gfilog[250] = 108;k_gfilog[251] = 216;
k_gfilog[252] = 173;k_gfilog[253] = 71; k_gfilog[254] = 142;
}

__syncthreads();
	
unsigned char mult;
int i;
int j;
	
int high_disk = (disks-CHECK_SYMBOLS);
__shared__ unsigned long fetch_tmp[THREAD_BLOCKSIZE];
__shared__ unsigned long accu[THREAD_BLOCKSIZE];
		
__shared__ unsigned char *local_accu;
local_accu = (unsigned char *)&accu[tx];

__shared__ unsigned char *local_fetch_tmp;
local_fetch_tmp = (unsigned char *)&fetch_tmp[tx];

//tx = thread id im block
//bx = block id des threads
//th = thread nummer

for(j=1; j<=CHECK_SYMBOLS; j++){
	mult = j;
	accu[tx] = 0;
	
	for(i=0; i<=high_disk; i++){
		fetch_tmp[tx] = *(unsigned long *)&DEVICE_DP[(i*DMA_BLOCKSIZE)+(th*8)];
	
		local_accu[0] ^= mult_gf_shader(local_fetch_tmp[0], mult, k_gflog, k_gfilog);
		local_accu[1] ^= mult_gf_shader(local_fetch_tmp[1], mult, k_gflog, k_gfilog);
		local_accu[2] ^= mult_gf_shader(local_fetch_tmp[2], mult, k_gflog, k_gfilog);
		local_accu[3] ^= mult_gf_shader(local_fetch_tmp[3], mult, k_gflog, k_gfilog);
		local_accu[4] ^= mult_gf_shader(local_fetch_tmp[4], mult, k_gflog, k_gfilog);
		local_accu[5] ^= mult_gf_shader(local_fetch_tmp[5], mult, k_gflog, k_gfilog);
		local_accu[6] ^= mult_gf_shader(local_fetch_tmp[6], mult, k_gflog, k_gfilog);
		local_accu[7] ^= mult_gf_shader(local_fetch_tmp[7], mult, k_gflog, k_gfilog);
	
		//iterate local matrix index i^j	
		mult = mult_gf_shader(mult, j, k_gflog, k_gfilog);
		}
	*(unsigned long *)&DEVICE_PQ[((j-1)*DMA_BLOCKSIZE)+(th*8)] = accu[tx];
	}

}



/**
 * This function implements multiplication on an GF(2) with lookup tables on the
 * gpu with preinitialized lookup tables at the shared memory.
 *
 * @param a		   : first operand
 * @param b		   : second operand
 * @param gflog[]  : logarithm table
 * @param gfilog[] : inverse logarithm table
 *
 * @returns			result of the GF(2) multiplication
 */

__device__ inline unsigned char mult_gf_shader(unsigned char a, unsigned char b, unsigned char gflog[], unsigned char gfilog[])
{
unsigned char sum_log;
int w = 8;
	
if(a==0 || b==0){return 0;}
	
sum_log = gflog[a] + gflog[b];
  
if(sum_log >= NW-1){sum_log -= NW-1;}
 
return gfilog[sum_log];
}



/**
 * Get cards buffer
 *
 * @returns			void
 */

static void inline get_card_mem(void)
{

if(mem_tag == 0){
	cudaMalloc((void **)&DEVICE_DP, DMA_BLOCKSIZE*256);
	cudaMalloc((void **)&DEVICE_CS, DMA_BLOCKSIZE*256);
	
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
cudaFree(DEVICE_DP);
cudaFree(DEVICE_CS);
}

//______________________________________________________________________________



/**
 * This function generates gflog and gfilog
 *
 * @returns			0 on success
 */

int setup_tables(void)
{
unsigned int b, log, x_to_w;

unsigned int prim_poly_8 = 0435;
unsigned int prim_poly = prim_poly_8;
int w = 8;
	
x_to_w = 1 << w;
gflog2 = (unsigned short *) malloc (sizeof(unsigned short) * x_to_w);
gfilog2 = (unsigned short *) malloc (sizeof(unsigned short) * x_to_w);

b = 1;
for (log = 0; log < x_to_w-1; log++){
	gflog2[b] = (unsigned short) log;
	gfilog2[log] = (unsigned short) b;
	b = b << 1;
	if(b & x_to_w){
	b = b ^ prim_poly;}
	}

printf("gflog[] :\n");
for (log = 0; log < x_to_w-1; log++){
	printf("%u, ",  gflog2[log]);
	}
	
printf("\ngflog[] :\n");
for (log = 0; log < x_to_w-1; log++){
	printf("k_gflog[%d] = %u;\n", log, gflog2[log]);
	}

printf("\n\ngfilog[] :\n");
for (log = 0; log < x_to_w-1; log++){
	printf("%u, ",  gfilog2[log]);
	}
	
printf("\ngflog[] :\n");
for (log = 0; log < x_to_w-1; log++){
	printf("k_gfilog[%d] = %u;\n", log, gfilog2[log]);
	}
	
return 0;
}



/**
 * The second function returns the amount of time, where the process 
 * is running. It uses the propper glibc function gettimeofday() which
 * extracts from the RTC
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
