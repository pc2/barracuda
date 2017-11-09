/**
 * \file
 * \brief	Pure C implementation of the raid6 userspace functions
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 11.5.2008
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

# include "raid6vanilla.h"

HOST inline unative_t SHLBYTE(unative_t v);
HOST inline unative_t MASK(unative_t v);


/**
 * This is a pure C version of gen_syndrome
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */

HOST void raid6_vanilla_gen_syndrome(int disks, size_t bytes, void **ptrs)
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

HOST inline unative_t SHLBYTE(unative_t v)
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

HOST inline unative_t MASK(unative_t v)
{
	unative_t vv;

	vv = v & NBYTES(0x80);
	vv = (vv << 1) - (vv >> 7); /* Overflow on the top bit is OK */
	return vv;
}

