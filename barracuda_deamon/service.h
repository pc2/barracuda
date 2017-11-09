/**
 * \file
 * \brief	library for helper functions
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
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

#ifndef __BARACUDA_SERVICE__
#define __BARACUDA_SERVICE__

# include "definitions.h"

/**
 * The second function returns the amount of time, where 
 * the process is running.
 *
 * @returns		Time
 */

HOST double gtd_second(void);
HOST double second(void);


/**
 * Generates a test datapointer for the gen_syndrome function, which can be used
 * by the validator or benchmarking functions.
 *
 * @param bytes				: # of bytes
 * @param number_of_disks	: Number of virtual data disks
 *
 * @returns				Datapointers were the data and syndrome gets saved in
 */

HOST void **allocate_host_example_dpointer( int bytes, int number_of_disks );

/**
 * Deallocates the example dpointer
 *
 * @param number_of_disks	: Number of virtual data disks
 *
 * @returns				Datapointers were the gft an syndrome gets saved in
 */

HOST void deallocate_host_example_dpointer( int number_of_disks, void **dptrs );

/**
 * Prints a dpointer to the console.
 *
 * @param disks			: # of disks
 * @param bytes			: # of bytes
 * @param **ptrs		: Datapointers were the gft an syndrome gets saved in
 *
 * @returns		# of disks
 */

HOST void print_dpointer(int disks, int bytes, void **ptrs);



/**
 * Inititalize the generation of additional system variables. This variables can
 * be get with the following functions :
 *
 * get_number_of_phys_cpus() : Get the number of SMP Processors in your system
 *
 * @param    void
 *
 * @returns	 void
 */

void set_internal_vars();



/**
 * This function returns the number of physical CPUs in the system. Mainly it 
 * returns the global variable NUMBER_OF_CPUS_INSTALLED, which is 1 per default
 * and set to the right number of CPUs by the function set_internal_vars().
 *
 * @param    void
 *
 * @returns	 int : number of CPUs in the system
 */

int get_number_of_phys_cpus();
#endif
