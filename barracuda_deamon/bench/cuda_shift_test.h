/**
 * \file
 * \brief	Benchmarking function for the CUDA bitshifting implementation
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 7.8.2008
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

#ifndef __TEST_CUDA_PERF_SHIFT__
#define __TEST_CUDA_PERF_SHIFT__

/**
 * Main routine which tests the SHIFT function for all defined block sizes. The
 * intervall is defined by the two preprocessors BL_SIZE_START and BL_SIZE_STOP
 *
 * @returns			void
 */

__host__ void test_cuda_shift_perf();


/**
 * This function tests bitshifting for CUDA without overhead
 *
 *
 * @returns		void
 */

__host__ void test_pure_shift( );

#endif
