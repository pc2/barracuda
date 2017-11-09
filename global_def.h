/**
 * \file
 * \brief	global userspace and kernelspace independend definition file.
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 16.9.2008
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

#ifndef __GLOBAL_DEFINITIONS__
#define __GLOBAL_DEFINITIONS__

#define TRUE 1==1

/*
 * Debug levels
 */

//#define DEBUG_LEVEL_1	 // Normal debug level for the control flow
//#define DEBUG_LEVEL_2	 // print syndrome on dpointer generator
//#define DEBUG_LEVEL_3  // IOCTL Callback debugging
//#define DEBUG_LEVEL_4  // Netlink debugging
//#define DEBUG_LEVEL_5  // Procfs debugging
//#define DEBUG_LEVEL_6  // mmap debugging
//#define DEBUG_LEVEL_7  // other kernelspace debugging
//#define DEBUG_LEVEL_8  // CUDA implementation dependend
#define VALIDATOR_EXPLICIT_OUTPUT

#define LOGLEVEL 5


/* defining bit-masks */

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

typedef struct syndrome_container{
	int disks;
	size_t bytes;
	void **ptrs;
	}syndrome_container;

#endif
