/**
 * \file
 * \brief	Benchmarking section
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
 * Date of creation : 31.5.2008
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

#ifndef BENCHMARK_MODE
#define BENCHMARK_MODE

#include "definitions.h"

/**
 * Benchmark main-routine.
 *
 * @param *mode						: what shall we benchmark.
 *									  Valid modes are :\n
 *									  DRYRUN -> for benchmarking the pure implementation speed\n
 * @param gen_syndrome_list[]		: function pointers
 * @param **implemenatation_names	: related names of each function
 * @param number_of_implementations	: # of implementations
 * @param c_mode					: implementation number
 *
 * @returns		void
 */

HOST void baracuda_benchmarker(	char *mode,
								syndrome_func gen_syndrome_list[],
								char **implemenatation_names,
								int number_of_implementations,
							    int c_mode );

#endif
