/**
 * \file
 * \brief	This head obtains all global definitions of structs and preps
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

#ifndef __DEFINITIONS__
#define __DEFINITIONS__

/*
 * Module dependent settings
 */

#define NUMBER_OF_DISKS 5
#define NUMBER_OF_LOOPS 10

#define TIMING gtd_second( )

/*
 * General type definitions
 */

#include <linux/types.h>

/*! \var typedef uint8_t  u8;
    \brief Architecture independent 8 bit integer*/

/*! \var typedef uint16_t  u16;
    \brief Architecture independent 16 bit integer*/

/*! \var typedef uint32_t  u32;
    \brief Architecture independent 32 bit integer*/

/*! \var typedef uint64_t  u64;
    \brief Architecture independent 64 bit integer*/

/*! \def NBYTES(x) 
	\brief Even od bitmask */

/*! \def NSIZE
	\brief How much bytes are in one integer */

/*! \def NSHIFT
	\brief Logarithmic shift */

/*! \def NSTRING
	\brief Identifier */

/*! \var typedef u32 unative_t
    \brief A type definition for a Architecture independent integer. */

/*! \var typedef u64 unative_t
    \brief A type definition for a Architecture independent integer. */

typedef __u8 u8;
typedef __u16 u16;
typedef __u32 u32;
typedef __u64 u64;

#define BITS_PER_LONG __WORDSIZE

#ifndef PAGE_SIZE
//#define PAGE_SIZE 4096
//#define PAGE_SIZE 513536
//#define PAGE_SIZE 1048576
#define PAGE_SIZE 2097152
//#define PAGE_SIZE 4194304
//#define PAGE_SIZE 10485760
#endif

/*! \def GEN_SYNDROME
	\brief Generic description of a gen_syndrome function */

/* TODO : this definition must go*/
#define GEN_SYNDROME (int disks, size_t bytes, void **ptrs)

typedef void (*syndrome_func)(int disks, size_t bytes, void **ptrs);

/*! \var typedef struct thread_container;
    \brief Container which gets passed on thred-creation for the daemon mode */

typedef struct thread_container{
	int c_mode;
	syndrome_func gen_syndrome;
	}thread_container;

/* Defines which are used to make the code compile under non cuda systems */

#ifdef NOCUDA
	#define HOST
	#define DEVICE
	#define GLOBAL
#endif

#ifndef NOCUDA
	#define HOST	__host__
	#define DEVICE 	__device__
	#define GLOBAL	__global__
#endif

#include "../global_def.h"

#endif
