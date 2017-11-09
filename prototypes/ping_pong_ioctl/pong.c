/**
 * \file
 * \brief	Userspace deamon for the IOCTL ping pong test
 *
 * @author	Dominic Eschweiler weiler@upb.de
 *
 * Status	: STABLE \n
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
int fd;
int io = 0;

char buffer[] = "pong";
	
fd = open("/dev/baracuda", O_RDONLY);
if( fd < 0){
	printf("open failed!!\n");
	return -1;
	}
printf("IOCTL handler opened!\n");

strcpy( (char *)&buffer, "pong");

while( TRUE ){
	io = ioctl(fd, IOCTL_GETVALUE, &buffer);
	//printf("%s\n", buffer);
	strcpy( (char *)&buffer, "pong");
	}

if(fd >= 0){ close(fd); }
return 0;
}
