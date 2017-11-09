/**
 * \file
 * \brief	dummy implementation of the raid6 userspace functions
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

# include "raid6dummy.h"

/**
 * This is a dummy version of gen_syndrome
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */

HOST void raid6_dummy_gen_syndrome(int disks, size_t bytes, void **ptrs)
{
memcpy(ptrs[disks-1], ptrs[0], bytes);
memcpy(ptrs[disks-2], ptrs[0], bytes);
}
