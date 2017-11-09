/**
 * \file
 * \brief	Multi error correcting rs-encoder
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
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

#ifndef __RAID6MULTI__
#define __RAID6MULTI__

#include "../definitions.h"

/**
 * This is a multi failure correcting version of gen_syndrome.
 *
 * @param disks		: # of disks
 * @param bytes		: # number of bytes
 * @param **ptrs	: processing data
 *
 * @returns			void
 */

HOST void multi_rs_gen_syndrome(int disks, size_t bytes, void **ptrs);

#endif
