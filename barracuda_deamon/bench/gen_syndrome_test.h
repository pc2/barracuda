/**
 * \file
 * \brief	This functions test the RS implmentations
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 14.8.2008
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

#ifndef GEN_SYNDROME_TEST
#define GEN_SYNDROME_TEST

# include "../service.h"

/**
 * Benchmarks the pure Speed of all registered implementations in a loops
 *
 * @param GEN_SYNDROME				: function pointer
 * @param **implemenatation_names	: related names of each function
 *
 * @param number_of_implementations	: # of implementations
 *
 * @returns		void
 */

HOST void compare_all_implementations(	void (*gen_syndrome_list[])GEN_SYNDROME, char **implemenatation_names, int number_of_implementations);

#endif
