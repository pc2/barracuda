/**
 * \file
 * \brief	Userspace deamon for the procfs ping pong test
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

#include <stdio.h>
#include <memory.h>
#include <malloc.h>
#include <unistd.h>
#include <time.h>
#include <termios.h>
#include <fcntl.h>
#include <errno.h>

#include <linux/netlink.h>
#include <bits/sockaddr.h>

#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/types.h>

#define IOCTL_GETVALUE 0x0001
#define TRUE 0==0
#define NPAGES 16


/**
 * IOCTL Benchmark main-routine.
 *
 * @param argc		: # of arguments
 * @param **argv	: Array of arguments
 *
 * @returns			EXIT_FAILURE on error, EXIT_SUCCESS on no error
 */

int main(int argc, char **argv)
{
FILE *fd;
int fp;
	
int io = 0;
unsigned long date;
	
char buffer[sizeof(unsigned long)+2];
char *string_buffer;
	
int len = getpagesize();

fd = fopen("/proc/baracuda/stub", "w+");
if( fd < 0){
	printf("proc stub open failed!!\n");
	return -1;
	}
printf("Procfs handler opened!\n");
	
while( TRUE ){
	fread( &buffer, sizeof(char), sizeof(unsigned long)+2, fd );
	
	/* do some calulations */
//	memcpy( &date, &buffer, sizeof(unsigned long));
//	string_buffer = (char *)date;
//	printf("Adress is : %u\n", date);
	
	/* send an acknollege */
	fwrite( "pong", sizeof(char), 5, fd );
	}


/* Close all file-pointer */
if(fd >= 0){ fclose(fd); }
if(fp >= 0){ close(fp); }

return 0;
}
