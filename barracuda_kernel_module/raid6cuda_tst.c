/**
 * \file
 * \brief	Barracuda testing module
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
 * Date of creation : 17.8.2008
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

#include <linux/kernel.h>
#include <linux/version.h>
#include <linux/module.h>

#include <linux/socket.h>
#include <net/sock.h>
#include <linux/netlink.h>
#include <net/tcp_states.h>
#include <linux/timer.h>
#include <linux/sched.h>


#include "raid6cuda.h"



#if BITS_PER_LONG == 64
# define NBYTES(x) ((x) * 0x0101010101010101UL)
# define NSIZE  8
# define NSHIFT 3
# define NSTRING "64"
typedef u64 unative_t;
#else
# define NBYTES(x) ((x) * 0x01010101U)
# define NSIZE  4
# define NSHIFT 2
# define NSTRING "32"
typedef u32 unative_t;
#endif


static void __exit mod_exit( void );
static int __init mod_init( void );
static int thread_code( void *data );

void raid6_vanilla_gen_syndrome(int disks, size_t bytes, void **ptrs);
static inline unative_t SHLBYTE(unative_t v);
static inline unative_t MASK(unative_t v);

extern void multi_rs_soft_gen_syndrome(int disks, size_t bytes, void **ptrs);
inline unsigned char mult_gf(unsigned char a, unsigned char b);

static int thread_id = 0;

DECLARE_MUTEX( dont_kill_mutex );

#define DURATIONS 100

/*
 * If this define is activated, the testbed benmarks the performance.
 * If not, a sample syndrome is calculated and result is shown at the
 * dmesg.
 */
#define BENCHMARK
//#define KERNELMODE

//#define TST_DEBUG

#define NUMBER_OF_DISK 7
// 4 K
//#define NPAGES 1
// 2 MB
#define NPAGES 512
// 10 MB
//#define NPAGES 2560 

#define BYTES (NPAGES*PAGE_SIZE)

#define CHECK_SYMBOLS 4
#define NW (1 << w)
//#define DEBUG_MULT_RS



/**
 * Thread function
 *
 * @param 			*data	: generic argument which gets passed on thread creation
 *
 * @returns			void
 */

static int thread_code( void *data )
{
#ifdef BENCHMARK	
int i, j;
int disks = 10;
void **dptrs;
	
unsigned long t1, t2, jiffie_timer, dur, timer;
//unsigned long timer;
//double timer;
double tmp_timer;
	
for(disks=5; disks <= 64; disks++){
	for(j=0; j < 10; j++){
		#ifdef TST_DEBUG
		printk("BM : 0\n");
		#endif
	
		dptrs=(void **)vmalloc( disks*sizeof(void *) );
		for(i=0; i < disks; i++ ){
			#ifdef TST_DEBUG
			printk("BM : 1\n");
			#endif

			dptrs[i] = vmalloc(BYTES);
			}

		/* Timing start */
		timer = 0;
		tmp_timer = 0;
		jiffie_timer = 0;
		dur = 0;

		// benchmark for at least 2 seconds
		while(jiffie_timer < (2*HZ) ){
			t1 = jiffies;
			#ifndef KERNELMODE
				raid6_cuda_gen_syndrome(disks, BYTES, dptrs);
			#endif
			
			#ifdef KERNELMODE
					raid6_vanilla_gen_syndrome(disks, BYTES, dptrs);
					multi_rs_soft_gen_syndrome(disks, BYTES, dptrs);
			#endif
			t2 = jiffies;
			
			if( time_after(t1, t2) == 0 )
				{ jiffie_timer = jiffie_timer + (t2 - t1);}
			else{ jiffie_timer = jiffie_timer + (t1 - t2);} 
			
			timer = timer + tmp_timer;
			dur++;
			}

		if(jiffie_timer != 0){ 
			timer = ((dur * BYTES)/(jiffie_timer/HZ)); }
		else{ 
			// Signal if there is anything going wrong
			// This could be happend if a function needs under one millisecond
			printk("%d ; nan\n", disks); }

		printk("%d ; %d\n", disks, timer );
		
		/* Timing end */
	
		#ifdef TST_DEBUG
		printk("BM : 3\n");
		#endif
	
		for ( i = 0; i < disks; i++ ) {
			vfree(dptrs[i]);
			}

		#ifdef TST_DEBUG
		printk("BM : 4\n");
		#endif
		vfree(dptrs);
		}
	}

barracuda_printk (0, "Test is ready\n" );

up(&dont_kill_mutex);
#endif
	
#ifndef BENCHMARK
int i, j;
int disks = NUMBER_OF_DISK;
void *dptrs[NUMBER_OF_DISK];
size_t bytes = 10;
char *tmp;
	
/* get space */
for ( i=0 ; i < disks ; i++ ){
	dptrs[i] = (char *) __get_free_pages(GFP_KERNEL, 1);
	if ( !dptrs[i] ){
		printk ("No memory for barracuda tests\n" );
		return -ENOMEM;
		}
	}
	
/* Fill space */
for ( i=0 ; i < disks ; i++ ){
	memset(dptrs[i], i, bytes);
	tmp = (char *)dptrs[i];
	for ( j=0 ; j < bytes ; j++ ){
		printk("%d", tmp[j]);
		}
	printk("\n\n");
	}
	
/* call barracuda */
raid6_cuda_gen_syndrome(disks, bytes, dptrs);
	
printk("mmapdrv: showing the last buffer state :\n");
for ( i=0 ; i < disks ; i++ ){
	tmp = (char *)dptrs[i];
	for ( j=0 ; j < bytes ; j++ ){
		printk("%d ", tmp[j]);
		}
	printk("\n");
	}
	
printk("mmapdrv: freeing virtual memory!\n");
for(i=0;i<disks;i++){
	free_pages((unsigned long)dptrs[i], 1);
	}
	
#endif
	
return 0;

}



/**
 * This function is called on an insmod.
 *
 * @param 			void
 *
 * @returns			void
 */

static int __init mod_init( void )
{
down(&dont_kill_mutex);
	
/* baracuda initialisation is neccessary*/
barracuda_start();

/* detach a thread */
thread_id = kernel_thread(thread_code, NULL, CLONE_KERNEL );
if(thread_id == 0){
	barracuda_printk (0, "Thread creation failed\n" );
	return -EIO; 
	}
barracuda_printk (0, "Created thread\n" );

return 0;
}



/**
 * This function is called on a rmmod.
 *
 * @param 			void
 *
 * @returns			void
 */

static void __exit mod_exit( void )
{
down(&dont_kill_mutex);

/* kill the thread */
if(thread_id){
	kill_proc( thread_id, SIGTERM, 1);
	barracuda_printk (0, "Killed thread" );
	}

barracuda_stop();
	
up(&dont_kill_mutex);
}



/**
 * This is a pure C version of gen_syndrome
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */

void raid6_vanilla_gen_syndrome(int disks, size_t bytes, void **ptrs)
{
	u8 **dptr = (u8 **)ptrs;
	u8 *p, *q;
	int d, z, z0;

	unative_t wd0, wq0, wp0, w10, w20;

	z0 = disks - 3;		/* Highest data disk */
	p = dptr[z0+1];		/* XOR parity */
	q = dptr[z0+2];		/* RS syndrome */

	for ( d = 0 ; d < bytes ; d += NSIZE ){
		wq0 = wp0 = *(unative_t *)&dptr[z0][d];
		for ( z = z0-1 ; z >= 0 ; z-- ) {
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
}



/**
 * The SHLBYTE() operation shifts each byte left by 1, *not*
 * rolling over into the next byte
 *
 * @param v		: Integer which should be shifted
 *
 * @returns		The shifted integer
 */

static inline unative_t SHLBYTE(unative_t v)
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

static inline unative_t MASK(unative_t v)
{
	unative_t vv;

	vv = v & NBYTES(0x80);
	vv = (vv << 1) - (vv >> 7); /* Overflow on the top bit is OK */
	return vv;
}


/* register functions */
module_init( mod_init ) ;
module_exit( mod_exit ) ;



//______________________________________________________________________________

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
	printk("byte %d\n", i);
	#endif
	
	for(j=high_disk; j<disks; j++){
		matrix_pos_y++;
		matrix_pos_x = matrix_pos_y;
		#ifdef DEBUG_MULT_RS
		printk("%u", matrix_pos_y);
		#endif
		
		dptrs[j][i] = 0;
		for(d=0; d<high_disk; d++){
			dptrs[j][i] ^= mult_gf(matrix_pos_x, dptrs[d][i]);
			#ifdef DEBUG_MULT_RS
			tmp = mult_gf(matrix_pos_x, dptrs[d][i]);
			printk("[(%u*%u) = %u] +", matrix_pos_x, dptrs[d][i], tmp);
			#endif
			matrix_pos_x  = mult_gf(matrix_pos_x, matrix_pos_y);
			}
		#ifdef DEBUG_MULT_RS
		printk("\b = %u\n", dptrs[j][i]);
		#endif
		}
	#ifdef DEBUG_MULT_RS
	printk("\n");
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
