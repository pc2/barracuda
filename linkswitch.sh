#!/bin/bash

FILE=$1
LINK_FILE=`echo $1 | sed 's/\.[^\.]*$//'`

FILE=`basename $FILE`

ln -s $FILE ./$LINK_FILE.c
