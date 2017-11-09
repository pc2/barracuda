/**
 * \file
 * \brief	Kernel module for a IOCTL ping pong test
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 27.8.2008
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
#include <linux/netlink.h>
#include <linux/ioctl.h>

#include <net/sock.h>
#include <net/tcp_states.h>
#include <asm/uaccess.h>

#define RUNS 1000
#define MAJOR_NUM 240
#define IOCTL_GETVALUE 0x0001

static int ioctl_callback(struct inode *inode, struct file *instanz, unsigned int cmd, unsigned long arg);
static void ioctl_test( void );
static int thread_code( void *data );
static int ping( char *buffer );

static struct file_operations ioctl_ops =
{
	.owner = THIS_MODULE,
	.ioctl = ioctl_callback,
};

static DECLARE_WAIT_QUEUE_HEAD(wait_queue_enter);
static DECLARE_COMPLETION( on_exit );
static int thread_id = 0;
static int wq_flag = 1;

static char *global_buffer;

static int major_num = 0;

DECLARE_MUTEX( callback_mutex );
DECLARE_MUTEX( ping_mutex );


/**
 * This function is called on an incoming ioctl
 *
 * @param 		*inode		inode
 * @param		*instanz	file instence
 * @param		cmd			ioctl command
 * @param		arg			ioctl command related argument
 *
 * @returns		-1 on fault, >= 0 on succes
 */

static int ioctl_callback(	struct inode *inode, 
							struct file *instanz, 
							unsigned int cmd, 
							unsigned long arg)
{
/* receive */
strcpy( global_buffer, (char *)arg);
wq_flag = 1;
wake_up_interruptible(&wait_queue_enter);
up( &callback_mutex );
		
/* send */
down( &callback_mutex );
wait_event_interruptible(wait_queue_enter, wq_flag==0);
if( copy_to_user( (void *)arg, global_buffer, 6) ){
	printk(KERN_INFO "ping_template : Warning, buffer usercopy failed!!!");
	}
return 0;
}



/**
 * This is the ping function
 *
 * @param 		*buffer		send buffer
 *
 * @returns		-1 on fault, >= 0 on succes
 */

static int ping( char *buffer )
{
down( &ping_mutex );

strcpy(global_buffer, buffer);
	
wq_flag = 0;
wake_up_interruptible(&wait_queue_enter);

wait_event_interruptible(wait_queue_enter, wq_flag==1);
buffer = global_buffer;

//printk(KERN_INFO "ping_template : %s\n", buffer );
up( &ping_mutex );
return 0;
}



/**
 * ping pong test
 *
 * @param 			void
 *
 * @returns			void
 */

static void ioctl_test( void )
{
int i;
long diff, t1, t2, msec;
	
/* send RUNS times ping and catch the related pong */	
t1   = jiffies;	

for(i=0; i<RUNS; i++){
	ping("ping");
	}
	
t2   = jiffies;
diff = t2 - t1;
msec = diff * 1000000 / HZ;
msec = msec / RUNS;

printk("ioctl_callback ; %ld\n", msec);	
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
int i = 0;
	
allow_signal( SIGTERM );

for(i=0; i<30; i++){
	ioctl_test();
	}

printk(KERN_INFO "ping_template : Test finnnished\n" );
	
complete_and_exit( &on_exit, 0);
	
return 0;
}



/**
 * This function is called on an insmod.
 *
 * @param 			void
 *
 * @returns			void
 */

static int __init mod_init( void )
{
printk(KERN_INFO "ping_template :  mod_init called\n" ) ;
	
global_buffer = (char *)kmalloc(6 * sizeof(char), GFP_KERNEL);

major_num = register_chrdev(major_num, "baracuda", &ioctl_ops);
	
if( major_num >= 0 ){
	printk(KERN_INFO "ping_template :  registered ioctl %d\n", major_num );
	
	thread_id = kernel_thread(thread_code, NULL, CLONE_KERNEL );
	if(thread_id == 0){
		return -EIO;
		}
	printk(KERN_INFO "ping_template :  created thread\n" ) ;
	
	return 0;
	}

printk(KERN_ERR "ping_template :  unable to register\n" );
return -EIO;
}



/**
 * This function is called on a rmmod.
 *
 * @param 			void
 *
 * @returns			void
 */

static void __exit mod_exit( void )
{
printk(KERN_INFO "ping_template : mod_exit called\n" ) ;
	
wait_for_completion( &on_exit );
if(thread_id){
	kill_proc( thread_id, SIGTERM, 1);
	}
printk(KERN_INFO "ping_template : thread killed\n" ) ;
	
unregister_chrdev(MAJOR_NUM, "baracuda");

kfree(global_buffer);
printk(KERN_INFO "ping_template :  unregistered ioctl %d\n", MAJOR_NUM );
}



/* register functions */
module_init( mod_init ) ;
module_exit( mod_exit ) ;
