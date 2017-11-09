/**
 * \file
 * \brief	Kernel module for a kernel-initiated netlink ping pong test
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

#include <linux/kernel.h>
#include <linux/version.h>
#include <linux/module.h>
#include <linux/init.h>
#include <linux/completion.h>
#include <linux/jiffies.h>

#include <net/tcp_states.h>
#include <net/sock.h>

#include <linux/socket.h>
#include <linux/netlink.h>
#include <linux/skbuff.h>

#include <linux/wait.h>
#include <linux/timer.h>

#define NETLINK_RS_SERVER 25
#define NL_COMMAND 0x11
#define MAX_PAYLOAD 1024
#define RUNS 1000

static void netlink_test( void );
static void nl_data_ready ( struct sk_buff *skb );
static int thread_code( void *data );
unsigned long micro_second(void);

static DECLARE_WAIT_QUEUE_HEAD(wait_queue_enter);
int wq_flag = 2;
static DEFINE_MUTEX(nl_mutex);

int thread_flag = 0;
static DECLARE_COMPLETION( on_exit );

static struct sock *nl_sk  = NULL;
struct sk_buff *skb_global = NULL;
static u32 pid;

static int thread_id = 0;


/**
 * Netlink callback server
 *
 * @param *skb		: netlink socket buffer for the incoming package
 *
 * @returns			void
 */

static void nl_data_ready ( struct sk_buff *skb )
{
wait_event_interruptible(wait_queue_enter, wq_flag==0);

skb_global = skb_copy(skb, 1);

wq_flag = 1;
wake_up_interruptible(&wait_queue_enter);
}



/**
 * generic blocking receive function
 *
 * @param 			void
 *
 * @returns			generic socket buffer
 */

static struct sk_buff *nl_recv_pkg( void )
{
wq_flag = 0;
wake_up_interruptible(&wait_queue_enter);
wait_event_interruptible(wait_queue_enter, wq_flag==1);
	
return skb_global;
}



/**
 * ping pong test
 *
 * @param 			void
 *
 * @returns			void
 */

static void netlink_test( void )
{
struct sk_buff  *skb;
struct sk_buff *ret_skb;
	
struct nlmsghdr *nlh;
struct nlmsghdr *hdr;

char *data_ptr;
	
int i;
long diff, t1, t2, msec;
	
/* get the first packet with the pid */
skb = nl_recv_pkg();
nlh = nlmsg_hdr(skb);
pid = nlh->nlmsg_pid;

kfree_skb(skb);
	
/* send RUNS times ping and catch the related pong */	
t1   = jiffies;	

for(i=0; i<RUNS; i++){
	ret_skb = nlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL);
	hdr = nlmsg_put(ret_skb, 0, 1, NLMSG_DONE, strlen("ping"), 0);
	data_ptr = nlmsg_data(hdr);
	strcpy(data_ptr, "ping");
	netlink_unicast(nl_sk, ret_skb, pid, MSG_WAITALL);
	
	skb = nl_recv_pkg();
	nlh = nlmsg_hdr(skb);
	pid = nlh->nlmsg_pid;
	
	kfree_skb(skb);
	}
	
t2   = jiffies;
diff = t2 - t1;
msec = diff * 1000000 / HZ;
msec = msec / RUNS;

printk("nl_kspi ; %ld\n", msec);
	
}



/**
 * Thread function
 *
 * @param 			*data	: generic argument which gets passed on thread creation
 *
 * @returns			void
 */

static int thread_code( void *data )
{
allow_signal( SIGTERM );
	
while(thread_flag == 0){
	netlink_test();
	}

complete_and_exit( &on_exit, 0);
	
return 0;
}



/**
 * This function is called on an insmod
 * and the related server.
 *
 * @param 			void
 *
 * @returns			void
 */

static int __init mod_init( void )
{
printk(KERN_INFO "ping_template :  mod_init called\n" ) ;

nl_sk = netlink_kernel_create(	&init_net, NETLINK_RS_SERVER, 0, nl_data_ready, &nl_mutex, THIS_MODULE );
printk(KERN_INFO "ping_template :  created netlink listener\n" ) ;
	
thread_id = kernel_thread(thread_code, NULL, CLONE_KERNEL );
if(thread_id == 0){
	return -EIO;
	}
printk(KERN_INFO "ping_template :  created thread\n" ) ;

return 0 ;
}



/**
 * This function is called on a rmmod, mainly it kills the netlink-socket
 *
 * @param 			void
 *
 * @returns			void
 */

static void __exit mod_exit( void )
{
printk(KERN_INFO "ping_template : mod_exit called\n" ) ;

thread_flag = 1;
wait_for_completion( &on_exit );
if(thread_id){
	kill_proc( thread_id, SIGTERM, 1);
	}
printk(KERN_INFO "ping_template : thread killed\n" ) ;
	
if(nl_sk){
	sock_release(nl_sk->sk_socket);
	}
printk(KERN_INFO "ping_template : socket terminated\n" ) ;
}



/**
 * The gtd_second function returns the amount of time, where the process 
 * is running.
 *
 * @returns		Time
 */

unsigned long micro_second(void)
{
	struct timeval t;
	do_gettimeofday(&t);

	return (unsigned long)t.tv_usec;
}



/* register functions */
module_init( mod_init ) ;
module_exit( mod_exit ) ;
