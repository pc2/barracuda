/**
 * \file
 * \brief	Benchmarking section
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
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

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>
#include <time.h>
#include <sys/time.h>
#include <math.h>

#ifndef NOCUDA
	#include <cuda_runtime_api.h>
	# include "bench/cuda_xor_test.h"
	# include "bench/cuda_shift_test.h"
#endif

# include "bench/gen_syndrome_test.h"

# include "benchmarker.h"
# include "service.h"



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
								int number_of_implementations, int c_mode )
{

if( strcmp(mode, "DRYRUN") == 0 ){
	printf("Starting DRYRUN test for testing all implementations.\n");
	compare_all_implementations(	gen_syndrome_list, 
									implemenatation_names,
									c_mode );
	}

#ifndef NOCUDA
if( strcmp(mode, "CUDA_BANDWIDTH") == 0 ){
	printf("Starting CUDA_BANDWIDTH for testing the bandwidth beteween host and cuda device.\n");
	}

if( strcmp(mode, "CUDA_XOR") == 0 ){
	printf("Starting CUDA_XOR for testing the pure XOR performance.\n");
	test_cuda_xor_perf();
	}
	
if( strcmp(mode, "CUDA_SHIFT") == 0 ){
	printf("Starting CUDA_SHIFT for testing the pure SHIFT performance.\n");
	test_cuda_shift_perf();
	}
#endif
	
}
