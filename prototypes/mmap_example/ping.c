/**
 * \file
 * \brief	Kernel module example for mmap
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	    : STABLE\n
 * Date of creation : 10.10.2008
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
#include <linux/mm.h>

#include <linux/version.h>
#include <linux/module.h>
#include <linux/socket.h>
#include <linux/netlink.h>
#include <linux/ioctl.h>

#include <net/sock.h>
#include <net/tcp_states.h>
#include <asm/uaccess.h>

#include <linux/errno.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/vmalloc.h>


#include <asm/semaphore.h>
#include <asm/atomic.h>

#include "exchange.h"

#define NPAGES 16
#define NUMBER_OF_DISK 7
#define BYTES 100

int mmap_mmap(struct file *file, struct vm_area_struct *vma);
int mmap_open(struct inode *inode, struct file *file);
int mmap_release(struct inode *inode, struct file *file);
int mmap_open(struct inode *inode, struct file *file);

int map_mem(struct file *file, struct vm_area_struct *vma, void *data);
int map_vmem(struct file *filp, struct vm_area_struct *vma, void *data);
int map_kmem(struct file *filp, struct vm_area_struct *vma, void *data);
syndrome_container *pack_smc(int disks, size_t bytes, void **ptrs);

unsigned int major = 0;
int disks = NUMBER_OF_DISK;
void *dptrs[NUMBER_OF_DISK];
//size_t bytes = PAGE_SIZE+BYTES;
size_t bytes = BYTES;

syndrome_container *snc;


static struct file_operations mmapdrv_fops =
{
owner:   THIS_MODULE,
mmap:    mmap_mmap,
open:    mmap_open,
release: mmap_release,
};



/**
 * //PORT
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
#endif
	
/* At offset 0 we map the marshalling sruct */
if (i == 0){
	#ifdef DEBUG_LEVEL_6
	printk("mmapdrv: mapping marshalling struct %p\n", snc);
	#endif
	return map_mem(file, vma, snc);
	}
	
/* At offset > 0 we map the syndromes */
if (i > 0) {
	#ifdef DEBUG_LEVEL_6
	printk("mmapdrv: remmaping disks data %p\n", snc);
	#endif
	return map_mem(file, vma, snc->ptrs[i-1]);
	}
	
/* at any other offset we return an error */
return -EIO;
}



/**
 * //PORT
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
printk("This is %d\n", ret);
#endif
	
if( ret == 1){
	return map_vmem(file, vma, data);
	}
else{
	return map_kmem(file, vma, data);
	}
}




/**
 * //PORT
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
 * //PORT
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

return 0;
}



/**
 * //PORT
 * Packing function for the marshalling struct. All arguments are packet to the
 * marshalling struct.
 *
 * @param 			disks  : number of disks
 * @param 			bytes  : number of bytes
 * @param			**ptrs : disks pointers
 *
 * @returns			void
 */

syndrome_container *pack_smc(int disks, size_t bytes, void **ptrs)
{
int i;
void **int_dptrs;
syndrome_container *syndrome_conti;

#ifdef DEBUG_LEVEL_6
printk("mmapdrv: 1 %d\n", disks);
#endif
syndrome_conti = (syndrome_container *)vmalloc(sizeof(syndrome_container));
if (syndrome_conti == NULL){
	printk("mmapdrv: pack_smc allocating syndrome_conti failed\n");
	return NULL;
	}

#ifdef DEBUG_LEVEL_6
printk("mmapdrv: 2 %p\n", syndrome_conti);
#endif
int_dptrs = vmalloc(disks * sizeof(void*));
if (int_dptrs == NULL){
	printk("mmapdrv: pack_smc allocating dptrs failed\n");
	return NULL;
	}
	
#ifdef DEBUG_LEVEL_6
printk("mmapdrv: 3\n");
#endif
for(i=0; i < disks; i++){
	int_dptrs[i] = ptrs[i];
	}
	
#ifdef DEBUG_LEVEL_6
printk("mmapdrv: 4\n");
#endif
syndrome_conti->disks = disks;
syndrome_conti->bytes = bytes;
syndrome_conti->ptrs  = int_dptrs;

#ifdef DEBUG_LEVEL_6
printk("mmapdrv: snc mapped\n");
#endif
return syndrome_conti;
}



/**
 * //PORT
 * Kill a marshalling struct
 *
 * @param			*syndrome_conti : marshalling struct
 *
 * @returns			void
 */

void kill_smc( syndrome_container *syndrome_conti )
{
vfree(syndrome_conti->ptrs);
vfree(syndrome_conti);
}



/**
 * called on the fopen on the devfs files
 *
 * @param 			inode : The inode of the devfs file
 * @param 			file  : The filepointer of the devfs file
 *
 * @returns			void
 */

int mmap_open(struct inode *inode, struct file *file)
{
return(0);
}



/**
 * called on the fclose on the devfs files
 *
 * @param 			inode : The inode of the devfs file
 * @param 			file  : The filepointer of the devfs file
 *
 * @returns			void
 */

int mmap_release(struct inode *inode, struct file *file)
{
return(0);
}

//______________________________________________________________________________
/**
 * This function is called on an insmod.
 *
 * @param 			void
 *
 * @returns			void
 */

static int __init mod_init( void )
{
int i, j;
char *tmp;
	
printk("PAGE_SIZE : %lu\n", PAGE_SIZE);

/* get space */
for ( i=0 ; i < disks ; i++ ){
	dptrs[i] = (char *) __get_free_pages(GFP_KERNEL, 2);
	if ( !dptrs[i] ){
		printk ("No memory for barracuda tests\n" );
		return -ENOMEM;
		}
	}
	
/* Fill space */
for ( i=0 ; i < disks ; i++ ){
	memset(dptrs[i], i, bytes);
	tmp = (char *)dptrs[i];
	for ( j=0 ; j < bytes ; j++ ){
		printk("%d", tmp[j]);
		}
	printk("\n\n");
	}

/* pack it to a marshalling struct */
#ifdef DEBUG_LEVEL_6
printk("mmapdrv: return disks %p\n", snc);
#endif
		
snc = pack_smc(disks, bytes, dptrs);
	
#ifdef DEBUG_LEVEL_6
printk("mmapdrv: return disks %p\n", snc);
printk("mmapdrv: return disks %d\n", snc->disks);
#endif
	
/* create a character device */
printk("mmapdrv: getting a character device!\n");
if ( (major=register_chrdev(0, "ping", &mmapdrv_fops))<0 ){
	printk("mmapdrv: unable to register character device\n");
	return (-EIO);
	}
	
return(0);
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
int i, j;
char *tmp;

printk("mmapdrv: unregister character device!\n");
unregister_chrdev(major, "ping");

printk("mmapdrv: showing the last buffer state :\n");
for ( i=0 ; i < disks ; i++ ){
	tmp = (char *)dptrs[i];
	for ( j=0 ; j < bytes ; j++ ){
		printk("%d", tmp[j]);
		}
	printk("\n\n");
	}
	
printk("mmapdrv: freeing virtual memory!\n");
for(i=0;i<snc->disks;i++){
	free_pages((unsigned long)dptrs[i], 2);
	}

kill_smc( snc );
}



/* register functions */
module_init( mod_init ) ;
module_exit( mod_exit ) ;

MODULE_DESCRIPTION("mmap demo driver");
MODULE_AUTHOR("Dominic Eschweiler <weiler@upb.de>");
//MODULE_LICENSE("")
