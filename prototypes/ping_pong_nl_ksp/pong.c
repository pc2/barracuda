/**
 * \file
 * \brief	Userspace deamon for the netlink kernel-initiated ping pong test
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
 * Date of creation : 17.8.2008
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

#include <stdio.h>
#include <memory.h>
#include <malloc.h>
#include <unistd.h>
#include <linux/netlink.h>
#include <bits/sockaddr.h>
#include <sys/socket.h>

#include <time.h>

#include <sys/time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>

#define NETLINK_RS_SERVER 25
#define NL_COMMAND 0x11
#define MAX_PAYLOAD 1024
#define RUNS 1000

void gen_message_container(struct msghdr *msg);
void destroy_message_container(struct msghdr *msg);
void add_payload(struct msghdr *msg, char *payload);

void get_payload(struct msghdr *msg, char *payload);
double gtd_second(void);



/**
 * NL Benchmark main-routine.
 *
 * @param argc		: # of arguments
 * @param **argv	: Array of arguments
 *
 * @returns			EXIT_FAILURE on error, EXIT_SUCCESS on no error
 */

int main(int argc, char **argv)
{
struct sockaddr_nl src_addr, dst_addr;
struct nlmsghdr *nlh = NULL;
struct iovec iov;
int sock_fd;
int i = 0;
int j = 0;
	
/* create socket */
memset( &src_addr, 0, sizeof(src_addr));
src_addr.nl_family = AF_NETLINK;
src_addr.nl_pid = getpid();
src_addr.nl_groups = 0;
sock_fd = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_RS_SERVER);
bind(sock_fd, (struct sockaddr*)&src_addr, sizeof(src_addr));

struct msghdr msg_server;
gen_message_container( &msg_server );

struct msghdr msg_client;
gen_message_container( &msg_client );
	
char *buffer = (char *)malloc(sizeof(char)*MAX_PAYLOAD);

for(j=0; j<30; j++){
	add_payload( &msg_server, "init");
	sendmsg(sock_fd, &msg_server, 0);
	
	double timer = gtd_second();
	
	for(i=0; i<RUNS; i++){
		recvmsg(sock_fd, &msg_client, 0);
		get_payload( &msg_client, buffer);
		add_payload( &msg_server, "pong");
		sendmsg(sock_fd, &msg_server, 0);
		}

	timer = gtd_second() - timer;
	timer = (timer / RUNS) * 1000000;
	printf("Time taken : %f \n", timer);
	}

destroy_message_container( &msg_server);
destroy_message_container( &msg_client);
	
free(buffer);
close(sock_fd);
return 0;
}



/**
 * Generates the packet structure
 *
 * @param struct msghdr *msg		: packet datastructure
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

void destroy_message_container(struct msghdr *msg)
{
free(msg->msg_iov->iov_base);
free(msg->msg_iov);
free(msg->msg_name);
}



/**
 * Save the payload to a package for sending
 *
 * @param *msg					: Target function pointer
 * @param *payload				: Array pointer to the availaible implementations
 *
 * @returns			void
 */

void add_payload(struct msghdr *msg, char *payload )
{
struct nlmsghdr *nlh = msg->msg_iov->iov_base;
strcpy(NLMSG_DATA(nlh), payload);	
}



/**
 * Get the payload from a received package
 *
 * @param *msg					: Target function pointer
 * @param *payload				: Array pointer to the availaible implementations
 *
 * @returns			void
 */

void get_payload(struct msghdr *msg, char *payload)
{
struct nlmsghdr *nlh = msg->msg_iov->iov_base;
strcpy(payload, NLMSG_DATA(nlh));
}



/**
 * The gtd_second function returns the amount of time, where the process 
 * is running. It uses the propper glibc function gettimeofday() which
 * which extracts from the RTC
 *
 * @returns		Time
 */

double gtd_second(void)
{
	struct timezone tz;
	struct timeval t;
	gettimeofday(&t, &tz);

	return (double) t.tv_sec + ((double)t.tv_usec/1e6);
}
