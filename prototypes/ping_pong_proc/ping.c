/**
 * \file
 * \brief	Kernel module for a procfs ping pong test
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
 * Date of creation : 3.9.2008
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
#include <linux/init.h>
#include <linux/stat.h>
#include <linux/platform_device.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/proc_fs.h>
#include <linux/cdev.h>
#include <linux/mm.h>

#include <net/sock.h>
#include <net/tcp_states.h>

#include <asm/uaccess.h>
#include <asm/page.h>

#define RUNS 1000
#define NPAGES 16


/* Function definitions */
static int thread_code( void *data );
static int ping( char *buffer );
void kobj_release(struct kobject *kobj);
static void procfs_test( void );

static int proc_read(char *page, char **start, off_t off, int count, int *eof, void *data);
static int write_proc(struct file *file, const char __user *buffer, unsigned long count, void *data);

/* Global variables */
DECLARE_MUTEX( ping_mutex );
DECLARE_MUTEX( read_mutex );
DECLARE_COMPLETION( on_exit );

int thread_id;

static struct proc_dir_entry *proc_directory;
static struct proc_dir_entry *proc_file;

static DECLARE_WAIT_QUEUE_HEAD(wait_queue_enter);
static int wq_flag = 2;

static char *global_buffer;



static int proc_read(char *page, char **start, off_t off, int count, int *eof, void *data)
{
unsigned long back_adress;

down( &read_mutex );
//	printk(KERN_INFO "ping_template :  read called\n" );
	wait_event_interruptible(wait_queue_enter, wq_flag==0);
	
	back_adress = (unsigned long)&global_buffer;
//	printk(KERN_INFO "ping_template :  address is %lu %lu \n", (unsigned long)&global_buffer, back_adress );
	memcpy(page, &back_adress, sizeof(unsigned long) );
up( &read_mutex );	


*eof = 1;
return sizeof(unsigned long);
}



static int write_proc(struct file *file, const char __user *buffer, unsigned long count, void *data)
{
//printk(KERN_INFO "ping_template :  write called\n" );

wq_flag=2;
wake_up_interruptible(&wait_queue_enter);

return count;
}



/**
 * This function is the foreward defined call to the userspace.
 *
 * @param 		*buffer		send buffer
 *
 * @returns		-1 on fault, >= 0 on success
 */

static int ping( char *buffer )
{
down( &ping_mutex );
	
global_buffer = buffer;
wq_flag = 0;
wake_up_interruptible(&wait_queue_enter);


wait_event_interruptible(wait_queue_enter, wq_flag==2);
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

static void procfs_test( void )
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

printk("procfs_callback ; %ld\n", msec);
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
	procfs_test();
	}

printk(KERN_INFO "ping_template :  Test finnnished\n" );
	
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

proc_directory = proc_mkdir("baracuda", NULL);
if( !proc_directory ){
	printk(KERN_INFO "ping_template :  proc directory creation failed\n" ) ;
	return -EIO;
	}
	
proc_file = create_proc_entry( "stub", 0, proc_directory);
if( !proc_file ){
	printk(KERN_INFO "ping_template :  proc file creation failed (stub)\n" ) ;
	return -EIO;
	}
else{
	proc_file->read_proc = proc_read;
	proc_file->write_proc = write_proc;
	}
printk(KERN_INFO "ping_template :  procfs populated\n" ) ;

thread_id = kernel_thread(thread_code, NULL, CLONE_KERNEL );
if(thread_id == 0){
	return -EIO;
	}
printk(KERN_INFO "ping_template :  created thread\n" ) ;

//ping( "ping" );
return 0;

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
printk(KERN_INFO "ping_template :  mod_exit called\n" ) ;

wait_for_completion( &on_exit );
if(thread_id){
	kill_proc( thread_id, SIGTERM, 1);
	}
printk(KERN_INFO "ping_template :  thread killed\n" ) ;

remove_proc_entry("stub", proc_directory);
remove_proc_entry("baracuda", NULL);
printk(KERN_INFO "ping_template :  removed proc entries\n" ) ;
}



/* register functions */
module_init( mod_init ) ;
module_exit( mod_exit ) ;
