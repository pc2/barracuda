/**
 * \file
 * \brief	Main executable for the baracuda deamon
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
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
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>
#include <time.h>
#include <sys/time.h>
#include <math.h>
#include <sched.h>
#include <signal.h>
#include <sys/wait.h>
#include <syslog.h>

#ifndef NOCUDA
	#include <cuda_runtime_api.h>
#endif

# include "definitions.h"
# include "service.h"
# include "vanilla/raid6vanilla.h"
# include "smp/raid6smp.h"
# include "dummy/raid6dummy.h"
# include "multrs/raid6multrs.h"
#ifndef NOCUDA
	# include "cuda/raid6cuda.h"
#endif
# include "validator.h"
# include "benchmarker.h"
# include "userspace_driver.h"

int helper();
HOST syndrome_func choose_implementation(	syndrome_func gen_syndrome,
											syndrome_func gen_syndrome_list[],
											char *mode, char **implementation_names,
											int number );


/**
 * Main Function of control
 *
 * @param argc		: # of arguments
 * @param **argv	: Array of arguments
 *
 * @returns			EXIT_FAILURE on error, EXIT_SUCCESS on no error
 */

HOST int main( int argc, char *argv[] )
{	
	/**
	 Variables
	 */
	
#ifndef NOCUDA
	/* a list of implementation-pointers */
	syndrome_func gen_syndrome_implementations[] =
	{	raid6_vanilla_gen_syndrome, 
		raid6_smp_gen_syndrome, 
		raid6_dummy_gen_syndrome,
		multi_rs_gen_syndrome,
		raid6_cuda_gen_syndrome };
	
	/* a list of corresponding implementation names */
	char *implemenatation_names[16] = 
	{ "SOFT", "SMP", "DUMMY", "MULTI", "CUDA" };

	/* How many generator functions are there */
	int number_of_generators = 5;
#endif
	
#ifdef NOCUDA
	/* a list of implementation-pointers */
	syndrome_func gen_syndrome_implementations[] =
	{	raid6_vanilla_gen_syndrome, 
		raid6_smp_gen_syndrome, 
		raid6_dummy_gen_syndrome,
		multi_rs_gen_syndrome };
	
	/* a list of corresponding implementation names */
	char *implemenatation_names[16] =
	{ "SOFT", "SMP", "DUMMY", "MULTI"};

	/* How many generator functions are there */
	int number_of_generators = 4;
#endif
	
	
	/* This is _THE_ implemenatation */
	syndrome_func gen_syndrome = gen_syndrome_implementations[0];
	
	/* The normal iterator variable */
	int i = 0;
	
	/**
	 * Process all possible arguments :
	 * -d			: deamonize
	 * -m <type>	: mode = SOFT, CUDA, FPGA
	 * -k           : kill all deamons
	 * -B <type>	: Benchmark Mode = PP_NL BW_NL PP_CB BW_CB
	 * -V			: Validation Mode ( Validate all RS implementations against the pure software Version
	 * --help -h	: show help
 	 */
	
	#ifdef DEBUG_LEVEL_1
	printf("DEBUG 1 :  There where %d(-1) arguments given\n", argc);
	#endif
	
	int  deamonize	= 0;
	int  mode		= 0;
	char mode_type[10];
	int  benchmark	= 0;
	char benchmark_type[10];
	int  validation	= 0;
	int  kill		= 0;
	int	 c_mode		= 0;
	int  rs_mode    = 0;
	
	/* Init all internal variables */
	set_internal_vars();

	/*
	 * Go through all command-line arguments and set all coresponding 
	 * configuration variables. Command.line arguments can be shown by
	 * -h or --help.
	 */
	for(i=0; i < argc; i++){
		
		#ifdef DEBUG_LEVEL_1
		printf("DEBUG 1 :  %3d : %s \n", i, argv[i]);
		#endif
		
		if( (strcmp(argv[i], "-h") == 0) || (strcmp("--help", argv[i]) == 0) ){
			helper();
			return EXIT_SUCCESS;
			}
		
		if( strcmp( argv[i], "-V") == 0 ){
			validation	= 1;
			}
		
		if( (strcmp(argv[i], "-m") == 0) && (i < argc-1) ){
			mode = 1;
			strcpy(mode_type, argv[i+1]);
			printf("Processing-mode is : %s\n", mode_type);
			if( strcmp(argv[i+1], "SOFT")  == 0 ){ rs_mode = 0; }
			if( strcmp(argv[i+1], "SMP")   == 0 ){ rs_mode = 1; }
			if( strcmp(argv[i+1], "DUMMY") == 0 ){ rs_mode = 2; }
			if( strcmp(argv[i+1], "MULTI")  == 0 ){ rs_mode = 3; }
			if( strcmp(argv[i+1], "CUDA")  == 0 ){ rs_mode = 4; }
			}
		
		if( (strcmp(argv[i], "-B") == 0) && (i < argc-1) ){
			benchmark = 1;
			strcpy(benchmark_type, argv[i+1]);
			printf("Benchmark-mode is  : %s\n", benchmark_type);
			}
		
		if( strcmp(argv[i], "-d") == 0 ){
			deamonize = 1;
			printf("Deamon mode activated.\n");
			}
		
		if( strcmp(argv[i], "-k") == 0 ){
			kill = 1;
			printf("Deamon would be terminated.\n");
			}
		
		if( strcmp(argv[i], "-c") == 0 ){
			if( strcmp(argv[i+1], "NL")    == 0 ){ c_mode = 1; }
			if( strcmp(argv[i+1], "IOCTL") == 0 ){ c_mode = 2; }
			if( strcmp(argv[i+1], "PFS")   == 0 ){ c_mode = 3; }
			}
		}

	/*
	 * In case that the user calles stop deamon, this handler lead to a managed 
	 * state.
	 */
	FILE *fp;
	pid_t pid;
	char kill_command[100];
	if( kill == 1){
		fp = fopen("/tmp/baracuda_pid", "r");
		if(fp == NULL){
			printf("Can't open Pidfile\n");
			return EXIT_FAILURE;
			}
		
		fread( (void *)&pid, sizeof(pid_t), 1, fp );
		fclose(fp);	
		
		printf("PID is : %d \n", pid);
		
		/* kill, however, does not work!?*/
		//kill(pid, SIGALRM);
		
		/* this is a quick fix which works properly */
		sprintf( (char *)&kill_command, "%s%d", "/bin/kill -SIGALRM ", pid );
		printf("Kill command is : %s\n", kill_command);
		system(kill_command);
		
		return EXIT_SUCCESS;
		}

	/*
	 * A valid mode must be allways choosen, therefore search for a corresponding
	 * implementation to the input string.
	 */
	
	if(mode == 0){
		printf("No valid mode was set. Please set a mode with -m\n");
		printf("See -h for valid modes ...\n");
		return EXIT_FAILURE;
		}
	else{
		gen_syndrome = choose_implementation( gen_syndrome, gen_syndrome_implementations, 
							   mode_type, implemenatation_names, number_of_generators );
			
		}
	
	/*
	 * If the validation flag was choosen, run the validator. This validator checks
	 * if the given RS implementation does the same as the default native software
	 * implementation. This pease of code is located in validator.c ( and .h)
	 */
	
	if( validation == 1){

		if( validate_implemenataion( gen_syndrome, gen_syndrome_implementations) == EXIT_SUCCESS ){ 
			printf("Output is correct\n");
			return EXIT_SUCCESS;
			}
		else{
			printf("!!! The output from the choosen implemenation is not valid !!!\n");
			return EXIT_FAILURE;
			}

		}

	/*
	 * If the benchmark flag was choosen, run the benchmarker subroutine. The
	 * variable <benchmark_type> sets the related benchmark. A list of available
	 * benchmarks which are included in the deamon could be get by the command-
	 * line-argument --help or -h
	 */
	
	if( benchmark == 1){
		baracuda_benchmarker( 	benchmark_type, gen_syndrome_implementations, 
								implemenatation_names, number_of_generators, rs_mode);
		}
	
	/*
	 * If the deamonize flag was choosen, [clone] and therefore deamonize. The 
	 * related subroutines are implemented in userspace_driver.cu (and .h). This
	 * last function call starts the actual device driver for the RS-Calculations.
	 */

	thread_container tc;
	tc.c_mode = c_mode;
	tc.gen_syndrome = gen_syndrome;
	
	if( deamonize == 1){
		if(c_mode == 0){
			printf("No valid connection-mode was chosen, see -h or --help for all possible connection-types\n");
			}
		
		if( clone(&userspace_driver_main, &(stack[10000]), CLONE_VM | SIGCHLD, (void *)&tc) == -1 ){
			printf("Barracuda daemoninzing failed -> cloning failed\n");
			return EXIT_FAILURE;
			}
		printf("Daemon-Mode was called. Please check your logfile (maybe /var/log/messages) for success!\n");
		}
	else{
		printf("Foreground-Mode was called.\n");
		userspace_driver_main((void *)&tc);
		}
	
	return EXIT_SUCCESS;
}



/**
 * Choose the implementation corresponding to the mode
 *
 * @param gen_syndrome					: Target function pointer
 * @param gen_syndrome_list[]			: Array pointer to the availaible implementations
 * @param *mode							: Mode string
 * @param **implementation_names		: Names coresponding to the function pointers
 * @param number						: Number of implemenations
 *
 * @returns			Function pointer to the choosen implementation
 */

HOST syndrome_func choose_implementation(	syndrome_func gen_syndrome,
											syndrome_func gen_syndrome_list[],
											char *mode, char **implementation_names,
											int number )
{
	int i;

	gen_syndrome = gen_syndrome_list[0];

	for(i = 0; i < number; i++){
		if(strcmp( mode, implementation_names[i]) == 0){
			gen_syndrome = gen_syndrome_list[i];
			printf("%s as implementation was choosen!\n", implementation_names[i]);
			return gen_syndrome;
			}
		}
	
printf("No valid mode was set. Please set a mode with -m\n");
printf("See -h for valid modes ...\n Fallback to Software!\n");
return gen_syndrome;
}



/**
 * This functions prints only a help statement to the shell
 *
 * @returns			EXIT_FAILURE on error, EXIT_SUCCESS on no error
 */

HOST int helper()
{
	printf("This is the baracuda deamon.\n");
	printf("This machine is a %d bit architecture!\n", BITS_PER_LONG );
	printf(" --help -h    : show this help\n");
	printf(" -d           : deamonize\n");
	printf(" -k           : kill all deamons\n");
	printf(" -m <mode>    : Reed-Solomon implementation mode\n");
#ifndef NOCUDA
	printf("Valid modes are SOFT, CUDA, MULTI, SMP\n");
#endif
#ifdef NOCUDA
	printf("Valid modes are SOFT, MULTI, SMP\n");
#endif	
	printf(" -c <mode>    : Setup the connection mode\n");
	printf("Valid modes are NL, IOCTL, PFS\n");
	printf(" -V           : Validation-mode (Validate the choosen RS implementations against the pure software-version)\n");
	printf(" -B <mode>    : Benchmark-mode\n");
	printf("Valid modes are	DRYRUN, CUDA_BANDWIDTH, CUDA_XOR, CUDA_SHIFT\n");
	
	return EXIT_SUCCESS;
}


