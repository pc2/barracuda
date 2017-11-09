/**
 * \file
 * \brief	Kernel module for a netlink ping pong test
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

#include <linux/socket.h>
#include <net/sock.h>
#include <linux/netlink.h>
#include <net/tcp_states.h>

#define NETLINK_RS_SERVER 25
#define NL_COMMAND 0x11
#define MAX_PAYLOAD 1024

static struct sock *nl_sk = NULL;
static DEFINE_MUTEX(nl_mutex);



/**
 * Netlink ping-pong kernel. This module answers a "pong" for each 
 * incoming "ping"
 *
 * @param *skb		: netlink socket buffer for the incoming package
 *
 * @returns			void
 */

static void reed_solomon_netlink_server( struct sk_buff *skb )
{
struct nlmsghdr *nlh, *hdr;
u32 pid;
struct sk_buff *ret_skb;
char *data_ptr;

nlh = nlmsg_hdr(skb);
pid = nlh->nlmsg_pid;
	
printk(KERN_INFO	"ping_template :  pid %d, seq: %d, data : \"%s\"\n", 
					pid, nlh->nlmsg_seq, 
					(char *)nlmsg_data(nlh) ) ;

ret_skb = nlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL);
if( ret_skb == NULL){
	printk("%s: no mem\n", __FUNCTION__);
	return;
	}

hdr = nlmsg_put(ret_skb, 0, 
				nlh->nlmsg_seq, NLMSG_DONE, 
				strlen("pong"), 0);

if(IS_ERR(hdr)){
	printk("nlmsg_put failed\n");
	nlmsg_free(ret_skb);
	return;
	}

data_ptr = nlmsg_data(hdr);
strcpy(data_ptr, "pong");
nlmsg_end(ret_skb, nlh);

netlink_unicast(nl_sk, ret_skb, pid, MSG_DONTWAIT);

}


/**
 * This function is called on an insmod, mainly it creates the netlink-socket
 * and the related server.
 *
 * @param 			void
 *
 * @returns			void
 */

static int __init mod_init( void )
{
printk(KERN_INFO "ping_template :  mod_init called\n" ) ;

nl_sk = netlink_kernel_create(	&init_net, 
								NETLINK_RS_SERVER, 0, 
							  	reed_solomon_netlink_server, 
							  	&nl_mutex, THIS_MODULE );	
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
	if(nl_sk){
		sock_release(nl_sk->sk_socket);
		}
	printk(KERN_INFO "ping_template : socket terminated\n" ) ;
}



/* register functions */
module_init( mod_init ) ;
module_exit( mod_exit ) ;
