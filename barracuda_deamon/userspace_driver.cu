/**
 * \file
 * \brief	This is the userspace driver, which receives function-calls from the 
 *			userspace and delegates it to the choosen RS-Implementation.
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
 * Date of creation : 11.9.2008
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
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <syslog.h>
#include <sys/mman.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <bits/sockaddr.h>
#include <sys/socket.h>
#include <memory.h>
#include <malloc.h>
#include <sys/ioctl.h>

#ifndef NOCUDA
	#include <cuda_runtime_api.h>
	#include "cuda/raid6cuda.h"
#endif

#include "vanilla/raid6vanilla.h"
#include "smp/raid6smp.h"
#include "userspace_driver.h"
#include "definitions.h"
#include "service.h"

void kill_handler(int signum);
void alarm_handler(int signum);

int server_ioctl_callback(syndrome_func gen_syndrome);
int server_netlink(syndrome_func gen_syndrome);
int server_procfs(syndrome_func gen_syndrome);

syndrome_container *copy_act_syndrome_block( void );
void copyback_act_syndrome_block( syndrome_container *smc );

syndrome_container *get_act_syndrome_block( void );
void unget_act_syndrome_block( syndrome_container *smc );

void gen_message_container(struct msghdr *msg);
void destroy_message_container(struct msghdr *msg);
void add_payload(struct msghdr *msg, char *payload );
void get_payload(struct msghdr *msg, char *payload);


/* Variables */
volatile sig_atomic_t keep_going = 1;
volatile static int fd;

static syndrome_container *ret_global;
static int smc_flag = 0;
static void **global_dptrs;

/* Defines */
#define NETLINK_RS_SERVER 25
#define NL_COMMAND 0x11
#define MAX_PAYLOAD 1024
#define IOCTL_GETVALUE 0x0001

/* __Marshalling Method__
 * If this is undefined, the slow mmap method for marshalling is used. If this 
 * is defined, the copy_to_user method is used.
 */
//#define COPY_MARSHALLING


/*MAIN_THREAD_________________________________________________________________*/
/**
 * This is the main function of control which implements the userspace driver.
 * This part of code runs in a detached (demonized) process in the userspace.
 * All outputs at this parts are delegated to the syslog (/var/log /messages),
 * because a simple printf isn't possible on such an process.
 *
 * @param			*rs_function	: Signal number
 *
 * @returns			EXIT_FAILURE on error, EXIT_SUCCESS on no error
 */

int userspace_driver_main(void *rs_function)
{
pid_t pid = getpid();
struct stat status;
thread_container *tc;
int c_mode;
syndrome_func gen_syndrome;

/* Malloc the dptr array */
global_dptrs = (void **)malloc(255 * sizeof(void*));
	
/* reassemble the function pointer and the mode number */	
tc 				= (thread_container *)rs_function;
c_mode			= tc->c_mode;
gen_syndrome	= tc->gen_syndrome;
	
syslog(LOG_NOTICE, "Daemon-Mode called\n");
syslog(LOG_NOTICE, "Connection-Mode is %d\n", c_mode);
	
/* 
 store the pid into a file. This could also be used to look if there is 
 already baracuda process.
 */

if( stat("/tmp/baracuda_pid", &status) == 0 ){
	syslog(LOG_NOTICE, "There is already an existing pidfile !!!\n" );
	syslog(LOG_NOTICE, "If the baracuda-process isn't already running, please delete /tmp/baracuda_pid\n");
	return(EXIT_FAILURE);
	}
	
FILE *fp = fopen("/tmp/baracuda_pid", "w+");
if(fp == NULL){
	syslog(LOG_NOTICE, "Can't open Pidfile %d\n", pid );
	return EXIT_FAILURE;
	}
	
fwrite( (void *)&pid, sizeof(pid_t), 1, fp );
fclose(fp);

/* open /proc/baracuda/conf to pass the PID */
char proc_pass[50];

fp = fopen("/proc/barracuda/conf", "w+");
if(fp == NULL){
	syslog(LOG_NOTICE, "Can't open /proc/barracuda/conf for pid passing \n" );
	return EXIT_FAILURE;
	}
sprintf( (char *)&proc_pass, "pid=%d", pid);
fwrite( (void *)&proc_pass, strlen(proc_pass), 1, fp );
fclose(fp);
	
/* open /proc/baracuda/conf to setup a connection type */
fp = fopen("/proc/barracuda/conf", "w+");
if(fp == NULL){
	syslog(LOG_NOTICE, "Can't open /proc/barracuda/conf for mode passing \n" );
	return EXIT_FAILURE;
	}

switch( c_mode ){
	case 1 :	sprintf( (char *)&proc_pass, "con=NL");
				fwrite( (void *)&proc_pass, strlen(proc_pass), 1, fp );
				break;
	case 2 :	sprintf( (char *)&proc_pass, "con=IOCTL");
				fwrite( (void *)&proc_pass, strlen(proc_pass), 1, fp );
				break;
	case 3 :	sprintf( (char *)&proc_pass, "con=PROCFS");
				fwrite( (void *)&proc_pass, strlen(proc_pass), 1, fp );
				break;
	default :	return EXIT_FAILURE; 
}
		
fclose(fp);

/* Register a signal-handler which handles init.d stop call */

signal(SIGALRM, alarm_handler);

/* 
 * Register a signal-handler that catches the KILL calls to avoid unexpected
 * Hangups.
 */

signal(SIGTERM, kill_handler);
signal(SIGKILL, kill_handler);

/* open a filepointer for mmaping or copy_to_user */
fd=open("/dev/barracuda", O_RDWR);
if(fd < 0){
	syslog(LOG_NOTICE, "fd opening failed !\n");
	return(-1);
	}

/* Signal that everything is fine */
syslog(LOG_NOTICE, "Daemon-Mode established %d\n", pid );

/* Do something usefull */
switch( c_mode ){
	case 1 :	server_netlink(gen_syndrome);
				break;
	case 2 :	server_ioctl_callback(gen_syndrome);
				break;
	case 3 :	server_procfs(gen_syndrome);
				break;
	default :	putchar('\a'); 
}

/* cleanup section */

/* close the mmaping filepointer */
if(fd >= 0){ close(fd); }

/* delete lock */
remove("/tmp/baracuda_pid");

/* Free the dptr array */
free(global_dptrs);

syslog(LOG_NOTICE, "Mode number was : %d.\n", c_mode);
syslog(LOG_NOTICE, "Baracuda-Deamon terminated, please unload the kernel-module.\n");
return 0;
}



/**
 * This is the handler which catchs the singnal SIGKILL and SIGTERM. This is 
 * necessary, because a simple kill can lead to an undefined state which could 
 * cause the whole system to hang.
 *
 * @param signum	: Signal number
 *
 * @returns			void
 */

void kill_handler(int signum)
{
if( (signum == SIGKILL) || (signum == SIGTERM) ){
	syslog(LOG_NOTICE, "Kill called. Please use <barracuda stop> to shutdown into a secure state.\n");
	syslog(LOG_NOTICE, "This instance of baracuda will remain active!\n");
	/* Restart handler */
	signal (signum, kill_handler);
	}
}



/**
 * This is the signal handler which is called if the userspace frontend is instructed
 * to cleanup the userspace driver instance. The related signal could be called from 
 * baracuda_deamon.c with the command line option <-k>. Alternativly this could
 * be achieved bei calling <kill -SIGALRM [PID]> on the command line. BUT, if you
 * did this in that way you MUST delete the lockfile /tmp/baracuda_pid
 *
 * @param signum	: Signal number
 *
 * @returns			void
 */

void alarm_handler(int signum)
{
FILE *fp;
char flag = 'u';
	
if( signum == SIGALRM){
	/** 
 	 * Check if there are already used MD-devices. They must be unmounted and 
 	 * deregistered before the kernel module can be unloaded. The procfs-entry
	 * under </proc/barracuda/conf> inherits a 'n' if there are no mounted md-devices
	 * and 'u' when devices are mounted.
 	 */	
	
	fp = fopen("/proc/barracuda/conf", "r");
	if(fp == NULL){
		syslog(LOG_NOTICE, "Can't open /proc/barracuda/conf for shutdown checks\n" );
		return;
		}
	
	fread( (void *)&flag, sizeof(char), 1, fp );
	fclose(fp);
	
	if(flag == 'n'){
		syslog(LOG_NOTICE, "Shutdown called!!\n");
	
		/* Terminate all possible loops */
		keep_going = 0;
		syslog(LOG_NOTICE, "SIG Barrier set to zero.\n");
	
		/* Restart handler */
		signal (signum, alarm_handler);
		}
	else{ syslog(LOG_NOTICE, "Shutdown is not possible because ther are alread active RAID-Devices.\n"); }
	}
}



/*SUB_THREADS_________________________________________________________________*/
/**
 * This function is the userspace driver which is implementated with ioctl
 * callback method as the used connection technology.
 *
 * @param gen_syndrome	: 	Function Pointer to one of the RS implementations, which
 *							are located in the raid6*.cu files.
 *
 * @returns				a pointer to the actual syndrome block.
 */

int server_ioctl_callback(syndrome_func gen_syndrome)
{
int fd;
char buffer[] = "flag";

/* syndrome data */
int disks;
size_t bytes;
void **ptrs;
syndrome_container *act_container;

syslog(LOG_NOTICE, "IOCTL-Callback method called.\n");
	
/* Open device file for IOCTL handling */
	
fd = open("/dev/barracuda", O_RDONLY);
if( fd < 0){
	syslog(LOG_NOTICE, "IOCTL handler opening failed\n");
	return -1;
	}
syslog(LOG_NOTICE, "IOCTL handler opened!\n");
	
/* Loop until the deamon is killed */
	
while( keep_going ){
	/* Call the IOCTL */
	ioctl(fd, IOCTL_GETVALUE, &buffer);
	
	/* get actual syndrome pointer */
		
	#ifdef DEBUG_LEVEL_3	
	syslog(LOG_NOTICE, "next : get_act_syndrome_block\n");
	#endif

#ifdef COPY_MARSHALLING
	act_container = copy_act_syndrome_block();
#endif
#ifndef COPY_MARSHALLING
	act_container = get_act_syndrome_block();
#endif
	
	/* Disassemble container */
	disks = act_container->disks;
	bytes = act_container->bytes;
	ptrs  = act_container->ptrs;
	
	/* Pass to the gen syndrome function */
	#ifdef DEBUG_LEVEL_3
	syslog(LOG_NOTICE, "next : gen_syndrome\n");
	#endif
	
	gen_syndrome(disks, bytes, ptrs);
	
	/* unmap everything */
#ifdef COPY_MARSHALLING
	copyback_act_syndrome_block(act_container);
#endif
#ifndef COPY_MARSHALLING
	unget_act_syndrome_block(act_container);
#endif

	}
	
/* Close the opened IOCTL handler */
if(fd >= 0){ close(fd); }

return 0;
}



/**
 * This function is the userspace driver which is implemented with the netlink
 * method as the used connection technology.
 *
 * @param gen_syndrome	: 	Function Pointer to one of the RS implementations, which
 *							are located in the raid6*.cu files.
 *
 * @returns				a pointer to the actual syndrome block.
 */

int server_netlink(syndrome_func gen_syndrome)
{
/* netlink related stuff */
struct sockaddr_nl src_addr;
int sock_fd;
int bind_ret = 0;
	
struct msghdr msg_server;
struct msghdr msg_client;

/* syndrome data */
int disks;
size_t bytes;
void **ptrs;

#ifdef DEBUG_LEVEL_1
	unsigned long date;
#endif


char *buffer = (char *)malloc(sizeof(char)*MAX_PAYLOAD);
syndrome_container *act_container;

syslog(LOG_NOTICE, "Netlink method called.\n");

/* create socket */
sock_fd = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_RS_SERVER);
if(sock_fd < 0){
	syslog(LOG_NOTICE, "Can't create netlink socket.\n");
	exit(0);
	}
	
/* bind socket */
memset( &src_addr, 0, sizeof(src_addr));
src_addr.nl_family = AF_NETLINK;
src_addr.nl_pid = getpid();
src_addr.nl_groups = 0;
	
bind_ret = bind(sock_fd, (struct sockaddr*)&src_addr, sizeof(src_addr));

if( bind_ret < 0 ){
	syslog(LOG_NOTICE, "Can't bind netlink socket.\n");
	exit(0);
	}
	
gen_message_container( &msg_client );
gen_message_container( &msg_server );
	
while( keep_going ){
	/** 
	 * __first init every time__
	 * Netlink communication must always be initialised from the userspace and
	 * is not till then a bidirectional comunication method. For a correct 
	 * working messaging modell, we first have to send an empty packet to the
	 * kernelspace.
	 */
	
	#ifdef DEBUG_LEVEL_1
	syslog(LOG_NOTICE, "next : initial add_payload, sendmsg");
	#endif
		
	add_payload( &msg_server, "init");
	sendmsg(sock_fd, &msg_server, 0);
	
	/**
	 * If there is a syndrome that must be calculated, the kernel sends a message 
	 * to this handler.
	 */
	
	#ifdef DEBUG_LEVEL_1
	syslog(LOG_NOTICE, "next : recvmsg, get_payload");
	#endif
	
	recvmsg(sock_fd, &msg_client, 0);
	get_payload( &msg_client, buffer);
	
	#ifdef DEBUG_LEVEL_1
	memcpy( &date, &buffer, sizeof(unsigned long));
	syslog(LOG_NOTICE, "Adress is : %lu\n", date);
	#endif
		
	#ifdef DEBUG_LEVEL_1	
	syslog(LOG_NOTICE, "next : get_act_syndrome_block\n");
	#endif

	/* get actual syndrome pointer */
#ifdef COPY_MARSHALLING
	act_container = copy_act_syndrome_block();
#endif
#ifndef COPY_MARSHALLING
	act_container = get_act_syndrome_block();
#endif
	
	/* Disassemble container */
	disks = act_container->disks;
	bytes = act_container->bytes;
	ptrs  = act_container->ptrs;
	
	/* Pass to the gen syndrome function */
	#ifdef DEBUG_LEVEL_1
	syslog(LOG_NOTICE, "next : gen_syndrome\n");
	#endif
	
	gen_syndrome(disks, bytes, ptrs);
	
	/* unmap everything */
#ifdef COPY_MARSHALLING
	copyback_act_syndrome_block(act_container);
#endif
#ifndef COPY_MARSHALLING
	unget_act_syndrome_block(act_container);
#endif
	
	/* Acknowledge that all calculations are done */
	#ifdef DEBUG_LEVEL_1
	syslog(LOG_NOTICE, "next : add_payload\n");
	#endif
	
	add_payload( &msg_server, buffer);
	
	#ifdef DEBUG_LEVEL_1
	syslog(LOG_NOTICE, "next : sendmsg\n");
	#endif
		
	sendmsg(sock_fd, &msg_server, 0);
	}
	
close(sock_fd);

destroy_message_container( &msg_server);
destroy_message_container( &msg_client);
free(buffer);
	
return 0;
}



/**
 * This function is the userspace driver which is implementated with the procfs
 * method as the used connection technology.
 *
 * @param gen_syndrome	: 	Function Pointer to one of the RS implementations, which
 *							are located in the raid6*.cu files.
 *
 * @returns				a pointer to the actual syndrome block.
 */

int server_procfs(syndrome_func gen_syndrome)
{
FILE *fd;
syndrome_container *act_container;
char buffer[sizeof(unsigned long)+2];
#ifdef DEBUG_LEVEL_1
	double time;
	unsigned long date;
#endif

/*
int i,j;
char *tmp;
*/
	
/* syndrome data */
int disks;
size_t bytes;
void **ptrs;
	
syslog(LOG_NOTICE, "Procfs method called.\n");
	
fd = fopen("/proc/barracuda/stub", "w+");
if( fd < 0){
	syslog(LOG_NOTICE, "Proc stub open failed!!\n");
	return -1;
	}
syslog(LOG_NOTICE, "Procfs handler opened.\n");

while( keep_going ){
	fread( &buffer, sizeof(char), sizeof(unsigned long)+2, fd );
	
	#ifdef DEBUG_LEVEL_1
	memcpy( &date, &buffer, sizeof(unsigned long));
	syslog(LOG_NOTICE, "Adress is : %lu\n", date);
	#endif
	
	/* get actual syndrome pointer */
#ifdef COPY_MARSHALLING
	act_container = copy_act_syndrome_block();
#endif
#ifndef COPY_MARSHALLING
	act_container = get_act_syndrome_block();
#endif
	
	/* deassemble container */
	disks = act_container->disks;
	bytes = act_container->bytes;
	ptrs  = act_container->ptrs;
	
	/*
	for(i=0; i<disks; i++){
		tmp = (char *)ptrs[i];
		syslog(LOG_NOTICE, "%d\n", tmp[0]);
		}
	*/
	
	#ifdef DEBUG_LEVEL_1
	time = gtd_second();
	#endif
	/* pass to the gen syndrome function */
	gen_syndrome(disks, bytes, ptrs);
	#ifdef DEBUG_LEVEL_1
	time = gtd_second()-time;
	syslog(LOG_NOTICE, "TIME for gensyn() : %f milli\n", time*1000);
	#endif
	
	/* unmap everything */
#ifdef COPY_MARSHALLING
	copyback_act_syndrome_block(act_container);
#endif
#ifndef COPY_MARSHALLING
	unget_act_syndrome_block(act_container);
#endif
	
	/* acknowledge that all calculations are done */
	fwrite( &buffer, sizeof(char), sizeof(unsigned long)+2, fd );
	}
	
/* Close the file-pointer */
if(fd >= 0){ fclose(fd); }
	
return 0;
}



/*HELPER_FUNCTIONS____________________________________________________________*/
/**
 * Copy actual syndrome container from kernelspace via copy_to_user
 *
 * @returns	 syndrome_container * : A pointer to the actual syndrome
 *									which should be calculated.
 */

syndrome_container *copy_act_syndrome_block( )
{
#ifdef DEBUG_LEVEL_1
double time;
double total_time = 0;
#endif

int i;
syndrome_container *ret;
unsigned int pagesizen = getpagesize();

int disks;
size_t bytes;
void **dptrs = global_dptrs;

/* map the marshalling struct */
if(smc_flag == 0){
	ret_global = (syndrome_container *)mmap(0, sizeof(syndrome_container), PROT_READ, MAP_SHARED, fd, 0);
	if(ret_global == MAP_FAILED){
		perror("MMAPing marshalling struct failed !\n");
		return NULL;
		}
	smc_flag = 1;
	}
	
disks = ret_global->disks;
bytes = ret_global->bytes;
	
#ifdef DEBUG_LEVEL_1
	time = gtd_second();
#endif

/* malloc all data buffers */
for(i=0; i<disks; i++){
	dptrs[i] = (void *)malloc(bytes);
	}
	
#ifdef DEBUG_LEVEL_1
	time = gtd_second()-time;
	total_time = total_time + time;
	syslog(LOG_NOTICE, ">>> copy dpointer : %f milli\n", time*1000);
#endif

/* copy the stuff from the kernelspace */
for( i=0; i<disks-2; i++){
	pread(fd, dptrs[i], bytes, i);
	}
	
#ifdef DEBUG_LEVEL_1
	time = gtd_second();
#endif
	
/* malloc a syndrome container that resides at the userspace */
ret = (syndrome_container *)malloc( sizeof(syndrome_container) );

/* put all arguments into the marshalling struct */
ret->disks = disks;
ret->bytes = bytes;
ret->ptrs  = dptrs;

#ifdef DEBUG_LEVEL_1
	time = gtd_second()-time;
	total_time = total_time + time;
	syslog(LOG_NOTICE, ">>> put struct : %f milli\n", time*1000);
	syslog(LOG_NOTICE, "TOTAL mmap() -> %f milli\n", total_time*1000);
#endif
	
return ret;
}



/**
 * Copy back actual syndrome container to kernelspace via copy_to_user
 *
 * @param    smc : A pointer to the actual syndrome which should be calculated.
 *
 * @returns	 void
 */

void copyback_act_syndrome_block( syndrome_container *smc )
{
int disks		= smc->disks;
size_t bytes	= smc->bytes;
void **dptrs	= smc->ptrs;
	
int i;
	
/* copy all checksums back to the kernelspace */
pwrite(fd, dptrs[disks-2], bytes, disks-2);
pwrite(fd, dptrs[disks-1], bytes, disks-1);
	
/* free all buffers */
for(i=0; i<disks; i++){
	free(smc->ptrs[i]);
	}
free(smc);
}



/**
 * Get the actual syndrome container from the kernelspace
 *
 *
 * @returns	 syndrome_container * : A pointer to the actual syndrome
 *									which should be calculated.
 */

syndrome_container *get_act_syndrome_block()
{
#ifdef DEBUG_LEVEL_1
	double time;
	double total_time = 0;
#endif
int i;
syndrome_container *ret;
unsigned int pagesizen = getpagesize();

int disks;
size_t bytes;
void **dptrs = global_dptrs;
	
#ifdef DEBUG_LEVEL_1
	time = gtd_second();
#endif
/* map the marshalling struct */
if(smc_flag == 0){
	ret_global = (syndrome_container *)mmap(0, sizeof(syndrome_container), PROT_READ, MAP_SHARED, fd, 0);
	if(ret_global == MAP_FAILED){
		perror("MMAPing marshalling struct failed !\n");
		return NULL;
		}
	smc_flag = 1;
	}
#ifdef DEBUG_LEVEL_1
	time = gtd_second()-time;
	total_time = total_time + time;
	syslog(LOG_NOTICE, ">>> map marshal : %f milli\n", time*1000);
#endif

/* allocate pointers for the disks array */
disks = ret_global->disks;
bytes = ret_global->bytes;
		
/* map every disk pointer individually */
#ifdef DEBUG_LEVEL_1
	time = gtd_second();
#endif
for(i=1; i <= disks; i++){
	dptrs[i-1] = (void *)mmap(0, bytes, PROT_WRITE, MAP_SHARED, fd, i*pagesizen);
	
	if(dptrs[i-1] == MAP_FAILED){
		perror("MMAPing disk data failed !\n");
		return NULL;
		}
	}
#ifdef DEBUG_LEVEL_1
	time = gtd_second()-time;
	total_time = total_time + time;
	syslog(LOG_NOTICE, ">>> map dpointer : %f milli\n", time*1000);
#endif

#ifdef DEBUG_LEVEL_1
	time = gtd_second();
#endif
	
/* malloc a syndrome container that resides at the userspace */
ret = (syndrome_container *)malloc( sizeof(syndrome_container) );

/* put all arguments into the marshalling struct */
ret->disks = disks;
ret->bytes = bytes;
ret->ptrs  = dptrs;

#ifdef DEBUG_LEVEL_1
	time = gtd_second()-time;
	total_time = total_time + time;
	syslog(LOG_NOTICE, ">>> put struct : %f milli\n", time*1000);
	syslog(LOG_NOTICE, "TOTAL mmap() -> %f milli\n", total_time*1000);
#endif

return ret;
}



/**
 * Unmap the actual syndrome container via munmap
 *
 * @param *smc		: syndrome container to unmap
 *
 * @returns			void
 */

void unget_act_syndrome_block( syndrome_container *smc )
{
int i;
int disks = smc->disks;
size_t bytes = smc->bytes;

#ifdef DEBUG_LEVEL_1
	double time;
	double total_time = 0;
#endif

#ifdef DEBUG_LEVEL_1
	time = gtd_second();
#endif

/* First unmap all datapointer stuff */
for(i=0; i < disks; i++){
	munmap( smc->ptrs[i], bytes );
	}

#ifdef DEBUG_LEVEL_1
	time = gtd_second()-time;
	total_time = total_time + time;
	syslog(LOG_NOTICE, ">>> unmap dpointer : %f milli\n", time*1000);
#endif

#ifdef DEBUG_LEVEL_1
	time = gtd_second();
#endif

/* At last, free the marshalling struct */
free(smc);

#ifdef DEBUG_LEVEL_1
	time = gtd_second()-time;
	total_time = total_time + time;
	syslog(LOG_NOTICE, ">>> free smc : %f milli\n", time*1000);
	syslog(LOG_NOTICE, "TOTAL munmap() -> %f milli\n", total_time*1000);
#endif
}



/**
 * Generates the packet structure for the netlink protocoll.
 *
 * @param msg		: packet datastructure
 *
 * @returns			void
 */

void gen_message_container(struct msghdr *msg)
{
/* init payload package */
struct nlmsghdr *nlh = NULL;	
nlh = (struct nlmsghdr *)malloc(NLMSG_SPACE(MAX_PAYLOAD));
memset(nlh, 0, NLMSG_SPACE(MAX_PAYLOAD));

nlh->nlmsg_len   = NLMSG_SPACE(MAX_PAYLOAD);
nlh->nlmsg_pid   = getpid();
nlh->nlmsg_flags = NLM_F_REQUEST| NLM_F_ECHO;
nlh->nlmsg_type  = NL_COMMAND;
	
/* init iovec struct */
struct iovec *iov;
iov = (struct iovec *)malloc(sizeof(struct iovec));

iov->iov_base = (void *)nlh;
iov->iov_len  = nlh->nlmsg_len;

/* init struct for the destination adress */
struct sockaddr_nl *dst_addr;
dst_addr = (struct sockaddr_nl *)malloc(sizeof(struct sockaddr_nl));
memset( dst_addr, 0, sizeof(dst_addr));

dst_addr->nl_family = AF_NETLINK;
dst_addr->nl_pid = 0;
dst_addr->nl_groups = 0;

/* init struct msghdr */
memset( msg, 0, sizeof(struct msghdr));

msg->msg_name    = dst_addr;
msg->msg_namelen = sizeof(struct sockaddr_nl);
msg->msg_iov     = iov;
msg->msg_iovlen  = 1;
}



/**
 * Deallocates the netlink packet-header
 *
 * @param msg		: packet datastructure
 *
 * @returns			void
 */

void destroy_message_container(struct msghdr *msg)
{
free(msg->msg_iov->iov_base);
free(msg->msg_iov);
free(msg->msg_name);
}



/**
 * Save the payload to a Netlink-Package for sending
 *
 * @param *msg					: Target function pointer
 * @param *payload				: Array pointer to the availaible implementations
 *
 * @returns			void
 */

void add_payload(struct msghdr *msg, char *payload )
{
struct nlmsghdr *nlh;

#ifdef NOCUDA
	nlh = msg->msg_iov->iov_base;
#else
	nlh = (nlmsghdr *)msg->msg_iov->iov_base;
#endif

strcpy( (char *)NLMSG_DATA(nlh), payload );	
}



/**
 * Get the payload from a received Netlink-Package
 *
 * @param *msg					: Target function pointer
 * @param *payload				: Array pointer to the availaible implementations
 *
 * @returns			void
 */

void get_payload(struct msghdr *msg, char *payload)
{
struct nlmsghdr *nlh;

#ifdef NOCUDA
	nlh = msg->msg_iov->iov_base;
#else
	nlh = (nlmsghdr *)msg->msg_iov->iov_base;
#endif

strcpy(payload, (char *)NLMSG_DATA(nlh));
}
