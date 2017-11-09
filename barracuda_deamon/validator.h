/**
 * \file
 * \brief	Syndrome-generator validator
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
 * Date of creation : 21.5.2008
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

#ifndef __VALIDATOR__
#define __VALIDATOR__

# include "definitions.h"

/**
 * Generates a random datasaet to test the choosen implementation against
 * the vanilla version that was extracted from the kernel.
 * 
 *
 * @param gen_syndrome			: Target function pointer
 * @param gen_syndrome_list[]	: Array pointer to the availaible implementations
 *
 * @returns		EXIT_FAILURE if implmenations output is valid, 
 *              EXIT_SUCCESS if implmenations output is valid
 */

HOST int validate_implemenataion( syndrome_func gen_syndrome, syndrome_func gen_syndrome_list[] );
#endif

