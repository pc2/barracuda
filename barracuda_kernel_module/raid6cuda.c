/**
 * \file
 * \brief	Part of the kernelmodule which inherrits the barracuda connector
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE\n
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

#include <linux/cdev.h>
#include <linux/ioctl.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/mm.h>
#include <linux/netlink.h>
#include <linux/platform_device.h>
#include <linux/proc_fs.h>
#include <linux/socket.h>
#include <linux/stat.h>
#include <linux/sysfs.h>
#include <linux/slab.h>
#include <linux/skbuff.h>
#include <linux/timer.h>
#include <linux/version.h>
#include <linux/wait.h>

#include <net/sock.h>
#include <net/tcp_states.h>

#include <asm/uaccess.h>
#include <asm/page.h>

//#include "raid6.h"
#include "raid6cuda.h"
#include "../global_def.h"

/* Functions */

static int local_dev_open(struct inode *inode, struct file *fp);
static int local_dev_release(struct inode *inode, struct file *fp);

static int proc_write(struct file *file, const char __user *buffer, unsigned long count, void *data);
static int proc_read(char *page, char **start, off_t off, int count, int *eof, void *data);
static int conf_write(struct file *file, const char __user *buffer, unsigned long count, void *data);
static int conf_read(char *page, char **start, off_t off, int count, int *eof, void *data);

static int ioctl_callback( struct inode *inode, struct file *instanz, unsigned int cmd, unsigned long arg);

static void nl_data_ready ( struct sk_buff *skb );
static struct sk_buff *nl_recv_pkg( void );

static ssize_t barracuda_read( struct file *instance, char *user, size_t to_copy, loff_t *offset);
static ssize_t barracuda_write( struct file *instance, const char *user, size_t to_copy, loff_t *offset);

int mmap_mmap(struct file *file, struct vm_area_struct *vma);
int map_mem(struct file *file, struct vm_area_struct *vma, void *data);
int map_vmem(struct file *filp, struct vm_area_struct *vma, void *data);
int map_kmem(struct file *filp, struct vm_area_struct *vma, void *data);

/* Syndrome container handling functions */
syndrome_container pack_smc(int disks, size_t bytes, void **ptrs);
void kill_smc( syndrome_container *syndrome_conti );

/* One of these functions are delegated to a function pointer */
static int call_usp_proc(syndrome_container snc);
static int call_usp_ioctl(syndrome_container snc);
static int call_usp_nl(syndrome_container snc);

typedef int (*userspace_call)(syndrome_container snc);
userspace_call call_usp;

/* Defines */
#define MAJOR_NUM 240
#define IOCTL_GETVALUE 0x0001
#define NETLINK_RS_SERVER 25
#define NL_COMMAND 0x11
#define MAX_PAYLOAD 1024

#define NPAGES 16


/* Global var's */
/*
const struct raid6_calls raid6_cuda = {
	raid6_cuda_gen_syndrome,
	NULL,
	"int" NSTRING "x1",
	0
};
*/

static struct file_operations fops = {
.open		= local_dev_open,
.release	= local_dev_release,
.read		= barracuda_read,
.write		= barracuda_write,
.mmap		= mmap_mmap,
.owner		= THIS_MODULE,
.ioctl		= ioctl_callback,
};

//static int major_num = 0;
static struct proc_dir_entry *proc_directory;
static struct proc_dir_entry *proc_stub;
static struct proc_dir_entry *proc_conf;

static dev_t mmap_dev;
static struct cdev mmap_cdev;

static syndrome_container *actual_snc;

/*_GENSYNDROME_MAIN_FUNCTION__________________________________________________*/

DECLARE_MUTEX( gen_syndrome_mutex );

/**
 * This is the barracuda gen_syndrome stub. It gets the data, packs it to structur
 * and delegates them to the choosen marshalling function.
 *
 * @param 		disks		Number of disks
 * @param		bytes		Number of bytes
 * @param		ptrs		Datapointers
 *
 * @returns		void
 */

void raid6_cuda_gen_syndrome(int disks, size_t bytes, void **ptrs)
{
syndrome_container snc;
	
down( &gen_syndrome_mutex );
	
/* Pack the syndrome data to a structure*/	
snc = pack_smc(disks, bytes, ptrs);

#ifdef DEBUG_LEVEL_7
printk ("raid6_cuda_gen_syndrome\n");
#endif
	
/* Marshall it with the function which was choosen in <write_conf()> */
call_usp(snc);

/* deallocate the syndrome pointer */
kill_smc(&snc);
	
up( &gen_syndrome_mutex );
}



/**
 * This is the proc interface which can be found under /proc/ba
 *
 * @param 		*file		File pointer
 * @param		*buffer		Userpace pointer to the data which was passed to 
 *							/proc/barracuda/conf
 * @param		count		# of bytes
 * @param		*data		Datapointer
 *
 * @returns		0 success and -EFAULT or -EOVERFLOW on error
 */

static unsigned int PID	= 0;
static int configured	= 0;
DECLARE_MUTEX( conf_mutex );

static int conf_write(struct file *file, const char __user *buffer, unsigned long count, void *data)
{
int length = 40;
char input[length];
char *instruction;
char *value;

down( &conf_mutex );

/**
 * Check if there is already a valid configuration. If there is, the cuda gen 
 * syndrome is work in progress and we are not able to reconfigure.
 */
if(configured == 1){
	barracuda_printk (0, "Kernel Module is already configured!\n");
	barracuda_printk (0, "PID is %u\n", PID);
	return count;
	}
	
/* copy the string of the command initially to the kernelspace */
if (count > length){ return -EOVERFLOW; }
if (copy_from_user(&input, buffer, count)){
	return -EFAULT;;
  	}
input[count] = '\0';

barracuda_printk (0, "Command -> %s\n", input);

/**
 * First of all, a pid must be choosen. The barracuda deamon does this automatically
 * on its registration process.
 */
if( PID == 0){
	/** 
	 * First get the PID-Number of the userspace deamon for the netlink
	 * communication. This value should be initialized by the userspace deamon.
	 */
	value = input;
	instruction = strsep( &value, "=");

	barracuda_printk (1, "Inst  : %s\n", instruction);
	barracuda_printk (1, "Value : %s\n", value);
	
	if( strcmp(instruction, "pid") == 0 ){ 
		PID=simple_strtoul(value, (char **)instruction, 10); 
		barracuda_printk (1, "PID = %u\n", PID);
		}
	}
else{
	/**
	 * In the second step we set the configuration of the connection-type.
	 */
	value = input;
	instruction = strsep( &value, "=");
	
	barracuda_printk (1, "2 step \n");
	barracuda_printk (1, "Inst  : %s\n", instruction);
	barracuda_printk (1, "Value : %s\n", value);
	
	/**
	 * For this reason we construct a function pointer to the right implementation.
	 * This one gets used in the function <raid6_cuda_gen_syndrome()>
	 */
	if( strcmp(instruction, "con") == 0 ){
		barracuda_printk (1, "Choosing connection\n");
		
		/*con=NL*/
		if( strcmp(value, "NL") == 0 ){
			call_usp = call_usp_nl; 
			configured = 1;
			barracuda_printk (1, "configured = %d\n", configured);
			up( &gen_syndrome_mutex );
			}
	
		/*con=PROCFS*/
		if( strcmp(value, "PROCFS") == 0 ){
			call_usp = call_usp_proc;
			configured = 1;
			barracuda_printk (1, "configured = %d\n", configured);
			up( &gen_syndrome_mutex );
			}
	
		/*con=IOCTL*/
		if( strcmp(value, "IOCTL") == 0 ){ 
			call_usp = call_usp_ioctl; 
			configured = 1;
			barracuda_printk (1, "configured = %d\n", configured);
			up( &gen_syndrome_mutex );
			}
		
		/**
		 * After a pid and a connection-type was choosen, the gen_syndrome
		 * function is ready to use.
		 */
		}
	}

up( &conf_mutex );

return count;
}



/**
 * This function is redirected if there happens a read on </proc/barracuda/conf>
 * which returns a <"u"> if there are active RAID devices and a <"n"> if not. This
 * is necessary for the userspace deamon to check if there are outstanding requests
 * which are not served already.
 *
 * @param 		*page		Page were the returned data gets saved in
 * @param		**start		Adress to the first byte in the reurn data
 * @param		off			Offset
 * @param		count		How many bytes are in one page
 * @param		*eof		End Of File flag, shows if the data is ready
 * @param		*data		Pointer to the userspace data
 *
 * @returns		int > 0 as the size of the returned data
 */

static int conf_read(char *page, char **start, off_t off, int count, int *eof, void *data)
{
char nj[] = "n";
char jj[] = "u";
	
/* TODO : get the raid usage count */
if( TRUE ){ strcpy(page, nj); }
else{ strcpy(page, jj); }
	
*eof = 1;
return 3;
}



/*_PROCFS__IMPLEMENTATION_DEPENDEND___________________________________________*/
/**
 * Redirection stub for calling the userspace by the procfs method. Therefore
 * all input arguments for <gen_syndrome> get packed together to one syndrome-
 * container.
 *
 * @param 		*snc	This are the gen_syndrome arguments which should be 
 *						marshalled to the userspace.
 *
 * @returns		int > 0 as the size of the returned data
 */

static DECLARE_WAIT_QUEUE_HEAD(procfs_wq);
static int procfs_wq_flag = 2;
DECLARE_MUTEX( call_usp_proc_mutex );

static int call_usp_proc(syndrome_container snc)
{
down( &call_usp_proc_mutex );

memcpy(actual_snc, &snc, sizeof(syndrome_container) );
		
procfs_wq_flag = 0;
wake_up_interruptible(&procfs_wq);
wait_event_interruptible(procfs_wq, procfs_wq_flag==2);

up( &call_usp_proc_mutex );
return 0;
}



DECLARE_MUTEX( proc_read_mutex );

/**
 * This is the first part of the procfs based signaling concept. The function
 * <server_procfs()> located at <userspace_driver.cu> reads the next job from
 * </proc/barracuda/stub>, gets the syndrome data from a mmap routine, calculates
 * the syndromes and then calls proc_write for signaling that the job is done.
 *
 * @param 		*page		Page were the returned data gets saved in
 * @param		**start		Adress to the first byte in the reurn data
 * @param		off			Offset
 * @param		count		How many bytes are in one page
 * @param		*eof		End Of File flag, shows if the data is ready
 * @param		*data		Pointer to the userspace data
 *
 * @returns		int > 0 as the size of the returned data
 */

static int proc_read(char *page, char **start, off_t off, int count, int *eof, void *data)
{
unsigned long back_adress;

down( &proc_read_mutex );
	#ifdef DEBUG_LEVEL_5
	printk("proc_read called\n");
	#endif
	
	wait_event_interruptible(procfs_wq, procfs_wq_flag==0);
	back_adress = (unsigned long)&actual_snc;
	memcpy(page, &back_adress, sizeof(unsigned long) );
up( &proc_read_mutex );	

*eof = 1;
return sizeof(unsigned long);
}



DECLARE_MUTEX( proc_write_mutex );

/**
 * This is the second part of the procfs based signaling concept. This function
 * gets called, if the job is done. For more details please see the description
 * of <proc_read()>
 *
 * @param 		*file		File pointer
 * @param		*buffer		Userpace pointer to the data which was passed to 
 *							/proc/barracuda/conf
 * @param		count		# of bytes
 * @param		*data		Datapointer
 *
 * @returns		0 success and -EFAULT or -EOVERFLOW on error
 */

static int proc_write(struct file *file, const char __user *buffer, unsigned long count, void *data)
{
unsigned long back_adress;
unsigned long curr_adress = (unsigned long)&actual_snc;
	
down( &proc_write_mutex );

if( count < sizeof(unsigned long) ){ return -EOVERFLOW; }

if( copy_from_user(&back_adress, buffer, sizeof(unsigned long)) ){
	barracuda_printk (0, "copy_from_user failed in proc_write()\n", configured);
	return -EFAULT;;
  	}

if(back_adress != curr_adress){
	barracuda_printk (0, "Proc_write back adress is not the same\n", configured);
	return -EFAULT;;
	}
	
procfs_wq_flag=2;
wake_up_interruptible(&procfs_wq);

up( &proc_write_mutex );
return count;
}



/*_IOCTL__IMPLEMENTATION_DEPENDEND____________________________________________*/

DECLARE_MUTEX( call_usp_ioctl_mutex );
DECLARE_MUTEX( ioctl_init_mutex );
static DECLARE_WAIT_QUEUE_HEAD(ioctl_wq_enter);
static int ioctl_wq_enter_flag = 1;

/**
 * Redirection stub for calling the userspace by the IOCTL method. Therefore
 * all input arguments for gen_syndrome get packed together to one syndrome-
 * container.
 *
 * @param 		snc	This are the gen_syndrome arguments which should be 
 *						marshalled to the userspace.
 *
 * @returns		int > 0 as the size of the returned data
 */

static int call_usp_ioctl(syndrome_container snc)
{
down(&ioctl_init_mutex);
	
down(&call_usp_ioctl_mutex);
	memcpy(actual_snc, &snc, sizeof(syndrome_container) );
	
	ioctl_wq_enter_flag = 0;
	wake_up_interruptible(&ioctl_wq_enter);

	wait_event_interruptible(ioctl_wq_enter, ioctl_wq_enter_flag==1);
up(&call_usp_ioctl_mutex);
	
return 0;
}



DECLARE_MUTEX( ioctl_callback_mutex );

/**
 * This function is called on an incoming ioctl
 *
 * @param 		*inode		inode
 * @param		*instanz	file instence
 * @param		cmd			ioctl command
 * @param		arg			ioctl command related argument
 *
 * @returns		-1 on fault, >= 0 on success
 */

static int ioctl_callback(	struct inode *inode, 
							struct file *instanz, 
							unsigned int cmd, 
							unsigned long arg)
{
char buffer[5];

#ifdef DEBUG_LEVEL_3
printk(KERN_INFO "IOCTL called.\n");
#endif

/* Get the ioctl argument and check if it equals the "flag" string */
		
#ifdef DEBUG_LEVEL_3
printk(KERN_INFO "next strcpy and check\n");
#endif
		
strcpy( (char *)&buffer, (char *)arg);
	
if( strcmp(buffer, "flag") ){
	printk(KERN_INFO "No valid IOCTL calling!\n");
	}
	
/* Let the waitqueue accept new syndromes */
	
#ifdef DEBUG_LEVEL_3
printk(KERN_INFO "next wake_up_interruptible\n\n");
#endif
	
ioctl_wq_enter_flag = 1;
wake_up_interruptible(&ioctl_wq_enter);
	
up(&ioctl_init_mutex);
	
up( &ioctl_callback_mutex );
		
/* SEND______________________________________________________________________ */
down( &ioctl_callback_mutex );
	
/* Wait with returning until call_usp_ioctl() was triggered */
wait_event_interruptible(ioctl_wq_enter, ioctl_wq_enter_flag==0);

#ifdef DEBUG_LEVEL_3
printk(KERN_INFO "IOCTL SEND was called\n");
printk(KERN_INFO "next copy_to_user\n");
#endif

/* Return the string "flag" to signal that everything is OK*/
if( copy_to_user( (void *)arg, "flag", 5) ){
	printk(KERN_INFO "ping_template : Warning, buffer usercopy failed!!!");
	}

#ifdef DEBUG_LEVEL_3
printk(KERN_INFO "next return\n");
#endif
	
return 0;	
}



/*_NETLINK__IMPLEMENTATION_DEPENDEND__________________________________________*/

DECLARE_MUTEX( call_usp_nl_mutex );
static struct sock *nl_sk  = NULL;
static DEFINE_MUTEX(nl_mutex);
static DECLARE_WAIT_QUEUE_HEAD(nl_receive_queue);
int nl_receive_flag = 2;
struct sk_buff *skb_global = NULL;

/**
 * Redirection stub for calling the userspace by the netlink method. Therefore
 * all input arguments for gen_syndrome get packed together to one syndrome-
 * container.
 *
 * @param 		*snc	This are the gen_syndrome arguments which should be 
 *						marshalled to the userspace.
 *
 * @returns		int > 0 as the size of the returned data
 */

static int call_usp_nl(syndrome_container snc)
{
unsigned long back_adress;
unsigned long curr_adress;
	
struct sk_buff *skb;
struct sk_buff *ret_skb;
struct nlmsghdr *nlh;
struct nlmsghdr *hdr;
char *data_ptr;
char *ret_data_ptr;
u32 pid;
int status;
	
down(&call_usp_nl_mutex);
	/* get first a new package from the userspace */
	skb          = nl_recv_pkg();
	nlh = nlmsg_hdr(skb);
	pid = nlh->nlmsg_pid;
	
	if(PID != pid){
		printk("PIDs are defering.\n");
		return 1;
		}
	
	/* Set actual pointer and prepare it for passing to the userspace */
	memcpy(actual_snc, &snc, sizeof(syndrome_container) );
	
	back_adress = (unsigned long)&actual_snc;
	
	/* Put the pointer in a netlink packet */
	ret_skb = nlmsg_new(NLMSG_GOODSIZE, GFP_KERNEL);
	if(ret_skb == NULL){
		printk("There is no memory for the socket buffer.\n");
		return 1;
		}
	
	hdr = nlmsg_put(ret_skb, 0, 1, NLMSG_DONE, sizeof(unsigned long), 0);
	if( IS_ERR(hdr) ){
		printk("nlmsg_put failed.\n");
		return 1;
		}
	
	data_ptr = nlmsg_data(hdr);
	memcpy(data_ptr, &back_adress, sizeof(unsigned long) );

	/* send it to the userspace */
	#ifdef DEBUG_LEVEL_1
	printk("next unicast\n");
	#endif
	
	status = netlink_unicast(nl_sk, ret_skb, PID, MSG_DONTWAIT);
	if (status < 0){
		printk("Unicast failed\n");
		}
	
	/* wait for a response */
	skb          = nl_recv_pkg();
	
	#ifdef DEBUG_LEVEL_1
	printk("received\n");
	#endif
	
	/* copy the returned data */
	#ifdef DEBUG_LEVEL_1	
	printk("next nlmsg_hdr\n");
	#endif
		
	nlh          = nlmsg_hdr(skb);
	
	#ifdef DEBUG_LEVEL_1
	printk("next nlmsg_data\n");
	#endif
		
	ret_data_ptr = nlmsg_data(nlh);
	
	/* get the current returned adress */
	
	#ifdef DEBUG_LEVEL_1
	printk("next memcpy\n");
	#endif
		
	memcpy(&curr_adress, ret_data_ptr, sizeof(unsigned long) );

	/* Check if there is all going right */
	
	#ifdef DEBUG_LEVEL_1
	printk("next check\n");
	#endif

	if(back_adress != curr_adress){
		barracuda_printk (0, "Netlink back adress is not the same\n", configured);
		return -EFAULT;;
		}
	#ifdef DEBUG_LEVEL_1
	else{
		printk("Check successed\n");
		}
	#endif

	//kfree_skb(skb);
up(&call_usp_nl_mutex);

return 0;
}



/**
 * Netlink callback-server-function which is registered at the function 
 * <barracuda_start()> and deregistered in <barracuda_stop()>. It is associated
 * to a Netlink-socket <static struct sock *nl_sk> and called everytime if a
 * related netlink packet comes in. In combination with the wait queue <nl_receive_queue>
 * it is used to implement the blocking receive function <nl_recv_pkg()>.
 *
 * @param *skb		: netlink socket buffer for the incoming package
 *
 * @returns			void
 */

static void nl_data_ready( struct sk_buff *skb )
{
wait_event_interruptible(nl_receive_queue, nl_receive_flag==0);

#ifdef DEBUG_LEVEL_1
printk("data_read function was triggered\n");
#endif
	
if(skb_global != NULL){
	kfree_skb(skb_global);
	skb_global = NULL;
	}
skb_global = skb_copy(skb, 1);

#ifdef DEBUG_LEVEL_1
printk("skb copied\n");
#endif
	
nl_receive_flag = 1;
wake_up_interruptible(&nl_receive_queue);
}



/**
 * Netlink blocking receive function. This function blocks until it gets triggert
 * by the function <nl_data_ready()>. It can be used to receive a new package from
 * the registered netlink socket.
 *
 * @param 			void
 *
 * @returns			generic socket buffer
 */

static struct sk_buff *nl_recv_pkg( void )
{
nl_receive_flag = 0;
wake_up_interruptible(&nl_receive_queue);
wait_event_interruptible(nl_receive_queue, nl_receive_flag==1);
	
return skb_global;
}



/*_copy_to_user_MARSHALLING_IMPLEMENTATION_DEPENDEND__________________________*/
/**
 * Function for copying the marshalling structs data into the userspace.
 *
 * @param 			*instance	: The filepointer of the devfs file
 * @param 			*users		: Adress pointer from the userspace program
 * @param			to_copy		: data size
 * @param			*offset		: offset given by pread()
 *
 * @returns			void
 */

static ssize_t barracuda_read( struct file *instance, char *user, size_t to_copy, loff_t *offset)
{
int not_copied;
char *tmp;
int off = offset[0];

#ifdef DEBUG_LEVEL_6
printk("barracuda_read called, offset %d\n", off);
#endif
	
tmp = actual_snc->ptrs[off];
not_copied = copy_to_user(user, (void *)tmp, to_copy);

return to_copy;
}



/**
 * Function for copying the checksumms from userspace to kernelspace.
 *
 * @param 			*instance	: The filepointer of the devfs file
 * @param 			*users		: Adress pointer from the userspace program
 * @param			to_copy		: data size
 * @param			*offset		: offset given by pwrite()
 *
 * @returns			void
 */

static ssize_t barracuda_write( struct file *instance, const char *user, size_t to_copy, loff_t *offset)
{
int not_copied;
char *tmp;
int off = offset[0];

#ifdef DEBUG_LEVEL_6
printk("barracuda_write called, offset %d\n", off);
#endif
	
tmp = actual_snc->ptrs[off];
not_copied = copy_from_user( (void *)tmp, user, to_copy);
	
return to_copy;
}



/*_mmap()_MARSHALLING_IMPLEMENTATION_DEPENDEND________________________________*/
/**
 * Function for remapping the marshalling struct for the syndrome pointers to 
 * the userspace. The offset is used to reference disk that should be remapped 
 * in case.
 *
 * @param 			*file : The filepointer of the devfs file
 * @param 			*vma  : Virtual Area Management struct of the calling 
 *							userspace process
 *
 * @returns			void
 */

int mmap_mmap(struct file *file, struct vm_area_struct *vma)
{
unsigned long i = vma->vm_pgoff;
#ifdef DEBUG_LEVEL_6
printk("mmapdrv: mmap_mmap() called %lu\n", i);
	printk("disks : %d, bytes : %lu\n", actual_snc->disks, actual_snc->bytes);
#endif
	
/* At offset 0 we map the marshalling sruct */
if (i == 0){
	#ifdef DEBUG_LEVEL_6
	printk("mmapdrv: mapping marshalling struct %p\n", actual_snc);
	#endif
	return map_mem(file, vma, actual_snc);
	}
	
/* At offset > 0 we map the syndromes */
if (i > 0) {
	#ifdef DEBUG_LEVEL_6
	printk("mmapdrv: mapping disks data %p\n", actual_snc);
	#endif
	return map_mem(file, vma, actual_snc->ptrs[i-1]);
	}
	
/* at any other offset we return an error */
return -EIO;
}



/**
 * Function for remapping a kernelspace buffer which consists on virtual or
 * physical kernelspace memory.
 *
 * @param 			*file : The filepointer of the devfs file
 * @param 			*vma  : Virtual Area Management struct of the calling 
 *							userspace process
 * @param			*data : Data buffer which should be remapped to the 
 *							userspace
 *
 * @returns			void
 */

int map_mem(struct file *file, struct vm_area_struct *vma, void *data)
{
int ret = is_vmalloc_addr(data);

#ifdef DEBUG_LEVEL_6
printk("mmapdrv: This is %d\n", ret);
#endif
	
if( ret == 1){
	return map_vmem(file, vma, data);
	}
else{
	return map_kmem(file, vma, data);
	}
}



/**
 * Function for remapping a kernelspace buffer which consists on virtual 
 * kernelspace memory.
 *
 * @param 			*filp : The filepointer of the devfs file
 * @param 			*vma  : Virtual Area Management struct of the calling 
 *							userspace process
 * @param			*data : Data buffer which should be remapped to the 
 *							userspace
 *
 * @returns			void
 */

int map_vmem(struct file *filp, struct vm_area_struct *vma, void *data)
{
unsigned long pfn;
int ret;
long length = vma->vm_end - vma->vm_start;
unsigned long start = vma->vm_start;

#ifdef DEBUG_LEVEL_6
printk("mmapdrv: remapping virtual kernel memory\n");
#endif
	
/* For remapping virtual kernel memory we must remap each page individually */
while(length>0){
	pfn = vmalloc_to_pfn(data);
	ret = remap_pfn_range(vma, start, pfn, PAGE_SIZE, PAGE_SHARED);
	
	if (ret < 0){ return ret; }
	
	start  += PAGE_SIZE;
	data   += PAGE_SIZE;
	length -= PAGE_SIZE;
	}

return(0);
}



/**
 * Function for remapping a kernelspace buffer which consists on physical 
 * memory.
 *
 * @param 			*filp : The filepointer of the devfs file
 * @param 			*vma  : Virtual Area Management struct of the calling 
 *							userspace process
 * @param			*data : Data buffer which should be remapped to the 
 *							userspace
 *
 * @returns			void
 */

int map_kmem(struct file *filp, struct vm_area_struct *vma, void *data)
{
int ret;
long length = vma->vm_end - vma->vm_start;
unsigned long start = vma->vm_start;

if (length > NPAGES * PAGE_SIZE){
	return -EIO;}

#ifdef DEBUG_LEVEL_6
printk("mmapdrv: remapping physical kernel memory\n");
#endif
	
ret = remap_pfn_range( vma, start, virt_to_phys(data) >> PAGE_SHIFT, length,vma->vm_page_prot);
	
if (ret < 0){
	return ret;
	}

#ifdef DEBUG_LEVEL_6
printk("mmapdrv: remapping failed\n");
#endif
	
return 0;
}



/**
 * Packing function for the marshalling struct. All arguments are packet to the
 * marshalling struct.
 *
 * @param 			disks  : number of disks
 * @param 			bytes  : number of bytes
 * @param			**ptrs : disks pointers
 *
 * @returns			void
 */

syndrome_container pack_smc(int disks, size_t bytes, void **ptrs)
{
int i;
void **int_dptrs;
syndrome_container syndrome_conti;

#ifdef DEBUG_LEVEL_6
printk("pack_smc : 1 %d\n", disks);
#endif

int_dptrs = vmalloc(disks * sizeof(void*));
if (int_dptrs == NULL){
	printk("pack_smc : pack_smc allocating dptrs failed\n");
	syndrome_conti.ptrs  = NULL;
	syndrome_conti.disks = 0;
	syndrome_conti.bytes = 0;
	return syndrome_conti;
	}
	
#ifdef DEBUG_LEVEL_6
printk("pack_smc : 2\n");
#endif
for(i=0; i < disks; i++){
	int_dptrs[i] = ptrs[i];
	}
	
#ifdef DEBUG_LEVEL_6
printk("pack_smc : 3\n");
#endif
syndrome_conti.disks = disks;
syndrome_conti.bytes = bytes;
syndrome_conti.ptrs  = int_dptrs;

#ifdef DEBUG_LEVEL_6
printk("pack_smc : 4 smc packed\n");
#endif
return syndrome_conti;
}



/**
 * Kill a marshalling struct
 *
 * @param			*syndrome_conti : marshalling struct
 *
 * @returns			void
 */

void kill_smc( syndrome_container *syndrome_conti )
{
vfree(syndrome_conti->ptrs);
}



/*_INITIALISATION_AND_CLEANUP_________________________________________________*/
/**
 * This initialisation _MUST_ be called before the barracuda-connector could do
 * anything. It does some initialisation steps, such as creating the needed
 * PROCFS entries an assigning a file in /dev/ to the related functions. The called
 * functions could be found in this file. local_dev_mmap() is the callback for
 * mmap syscall, which marshalls the syndrome-data to the userspace. ioctl_callback()
 * is the function for the IOCTL-based message method. proc_read and proc_write
 * are used for the PROCFS-based connection method which relays to the file 
 * /proc/barracuda/stub. A configuration entry at the PROCFS is also given. It can
 * be found on /proc/barracuda/stub and the related callbacks are conf_read and 
 * conf_write.
 *
 * @returns		int 	O on success
 */

int barracuda_start( void )
{
barracuda_printk(0, "<mod_init> called\n" );

/** 
 * This mutex locks the cuda_gen_syndrome function until the PID and connection
 * type is configured.
 */
down( &gen_syndrome_mutex );
	
down(&ioctl_init_mutex);
	
/**
 *  Populate the PROCFS :
 *  This must be done for the the connection-type PROCFS which creates the file
 *  under /proc/barracuda/stub. The second file, which is created under 
 *  /proc/barracuda/conf is a generic configuration interface.
 */
	
proc_directory = proc_mkdir("barracuda", NULL);
if( !proc_directory ){
	barracuda_printk(0, "Proc-Directory creation failed\n" );
	return -EIO;
	}
	
proc_stub = create_proc_entry( "stub", 0, proc_directory);
if( !proc_stub ){
	barracuda_printk(0, "Proc-File creation failed (stub)\n" );
	return -EIO;
	}
else{
	proc_stub->read_proc  = proc_read;
	proc_stub->write_proc = proc_write;
	}

proc_conf = create_proc_entry( "conf", 0, proc_directory);
if( !proc_conf ){
	barracuda_printk(0, "Proc-File creation failed (conf)\n" );
	return -EIO;
	}
else{
	proc_conf->read_proc  = conf_read;
	proc_conf->write_proc = conf_write;
	}
	
barracuda_printk(0, "Procfs successfull populated\n" );

/**
 * Now we initialise a character-device. This is needed for two reasons. First
 * we need a device were we can bind the ioctl callback function for the related
 * systemcall. Second is needed for the mmap system call, which is further used
 * for marshalling the data from the kernel- to the user-space.
 */
	
if ( alloc_chrdev_region(&mmap_dev, 0, 1, "barracuda") < 0 ){
	barracuda_printk(0, "Could not allocate major number\n");
	return -EIO;
	}

cdev_init(&mmap_cdev, &fops);
if ( cdev_add(&mmap_cdev, mmap_dev, 1) < 0 ){
    barracuda_printk(0, "Could not allocate chrdev\n");
	unregister_chrdev_region(mmap_dev, 1);
	return -EIO;
	}

barracuda_printk(0, "/dev/barracuda character devices created\n" );

/**
 * At least we initialise a Netlink server.
 */
	
nl_sk = netlink_kernel_create(	&init_net, NETLINK_RS_SERVER, 
								0, nl_data_ready, &nl_mutex, 
							  	THIS_MODULE );
if( !nl_sk ){
	barracuda_printk(0, "Netlink socket creation failed\n");
	return -EIO;
	}
	
actual_snc = (syndrome_container * )vmalloc(sizeof(syndrome_container));
	
barracuda_printk(0, "Netlink socket successfull created\n" );
	
return 0;
}



/**
 * This is the barracuda power-off function, which _MUST_ be called on unloading
 * the module. It deletes all entries which were created at barracuda_start
 *
 * @returns		int 	O on success
 */

int barracuda_stop( void )
{
barracuda_printk(0, "<mod_exit> called\n" );

/* Remove all PROCFS entries */
remove_proc_entry("stub", proc_directory);
remove_proc_entry("conf", proc_directory);
remove_proc_entry("barracuda", NULL);

barracuda_printk(0, "Removed proc entries\n" );
	
/* Remove all /dev entries */
cdev_del(&mmap_cdev);
unregister_chrdev_region(mmap_dev, 1);
barracuda_printk(0, "/dev/barracuda unregistered\n");
	
/* Unload the netlink server */
if(nl_sk){ sock_release(nl_sk->sk_socket); }
barracuda_printk(0, "Netlink socket terminated\n" ) ;

vfree(actual_snc);

return 0;
}



/**
 * The used character-device is a stub with no character device specific 
 * functionallity behind. Only the syscall-handler are used. Therfore this
 * function is empty. Referenced by the <static struct file_operations fops>
 * at the head of this file.
 *
 * @param 		*inode	Inode of the related devce file
 * @param		*fp		Filepointer to this file
 *
 * @returns		int 	O on success
 */

static int local_dev_open(struct inode *inode, struct file *fp)
{
#ifdef DEBUG_LEVEL_1
barracuda_printk(5, "Device opened\n" );
#endif

return 0;
}



/**
 * The used character-device is a stub with no character device specific 
 * functionallity behind. Only the syscall-handler are used. Therfore this
 * function is empty. Referenced by the <static struct file_operations fops>
 * at the head of this file.
 *
 * @param 		*inode	Inode of the related devce file
 * @param		*fp		Filepointer to this file
 *
 * @returns		int 	O on success
 */

static int local_dev_release(struct inode *inode, struct file *fp)
{
#ifdef DEBUG_LEVEL_1
barracuda_printk(5, "Device released\n" );
#endif
	
return 0;
}



/*_HELPER_FUNCTIONS___________________________________________________________*/
/**
 * This is a debug-mode implementation of printk.
 *
 * @param 		loglevel	loglevel, 0 is the standard-output and 1,2,3,4,5 are debugs.
 *							The Loglevel is defined at LOGLEVEL at the head of this files.
 * @param		*logout		Format string like that one used in the printk-function
 *
 * @returns		void
 */

void barracuda_printk( int loglevel, char *logout, ...)
{
va_list args;
char *footer = (char *)vmalloc( 13+strlen(logout) );

va_start(args, logout);
sprintf(footer, "%s%s", "BARRACUDA :  ", logout);

/* Loglevel zero should be printed every time*/

if(loglevel == 0){ vprintk(footer, args); }
else{
	if(loglevel <= LOGLEVEL){ vprintk(footer, args); }
	}

va_end(args);
vfree(footer);
}
