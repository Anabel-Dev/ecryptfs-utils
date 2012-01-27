#!/bin/bash
#
# eCryptfs test suite harness
# Author: Tyler Hicks <tyhicks@canonical.com>
#
# Copyright (C) 2012 Canonical, Ltd.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA
#
# Example usage:
#
# # ./tests/run_tests.sh -K -c destructive -d /dev/vdb -l /lower -u /upper
#
# This would run kernel tests in the destructive category, as defined in
# kernel/tests.rc. /dev/vdb would be the block device containing the lower
# filesystem, which would be mounted at /lower. The eCryptfs mount point would
# be /upper.
#

run_tests_dir=$(dirname $0)
rc=1

. ${run_tests_dir}/lib/etl_funcs.sh

blocks=0
categories=""
device=""
disk_dir=""
kernel=false
ktests=""
lower_fs=""
lower_mnt=""
upper_mnt=""
userspace=false
utests=""

run_tests_cleanup()
{
	etl_remove_disk
	exit $rc
}
trap run_tests_cleanup 0 1 2 3 15

run_tests()
{
	test_dir=$1
	tests=$2

	for etest in $tests; do
		printf "%-16s\t" $(basename "$etest" .sh)

		${test_dir}/${etest}
		if [ $? -ne 0 ]; then
			rc=1
			printf "FAIL\n"
			exit
		fi

		printf "success\n"
	done
}

usage()
{
	echo "Usage: $(basename $0) [options] -K|-U -c categories -b blocks -l lower_mnt -u upper_mnt"
	echo "  or:  $(basename $0) [options] -K|-U -c categories -d device -l lower_mnt -u upper_mnt"
	echo
	echo "eCryptfs test harness"
	echo
	echo "  -b blocks	number of 1K blocks used when creating backing "
	echo "		disk for lower filesystem (not compatible "
	echo "		with -d)"
	echo "  -c categories	test categories to run (destructive, ...)"
	echo "  -D disk_dir	directory used to store created backing disk "
	echo "		when using -b (not compatible with -d)"
	echo "  -d device	backing device to mount lower filesystem, such "
	echo "		as /dev/sdd3 (not compatible with -b)"
	echo "  -f lower_fs	lower filesystem type (ext2, ext3, ext4)"
	echo "  -h		display this help and exit"
	echo "  -K		run tests relating to the kernel module"
	echo "  -l lower_mnt	destination path to mount lower filesystem"
	echo "  -U		run tests relating to the userspace utilities/"
	echo "  -u upper_mnt	destination path to mount upper filesystem"
}

while getopts "b:c:D:d:f:hKl:Uu:" opt; do
	case $opt in
	b)
		blocks=$OPTARG
		;;
	c)
		categories=$OPTARG
		;;
	d)
		device=$OPTARG
		;;
	D)
		disk_dir=$OPTARG
		;;
	f)
		lower_fs=$OPTARG
		;;
	h)
		usage
		rc=0
		exit
		;;
	K)
		kernel=true
		;;
	l)
		lower_mnt=$OPTARG
		;;
	U)
		userspace=true
		;;
	u)
		upper_mnt=$OPTARG
		;;
	\?)
		usage 1>&2
		exit
		;;
	:)
		usage 1>&2
		exit
		;;
	esac
done

if [ -z "$lower_mnt" ] || [ -z "$upper_mnt" ]; then
	# Lower and upper mounts must be specified
	usage 1>&2
	exit
elif [ "$blocks" -lt 1 ] && [ -z "$device" ]; then
	# Must specify blocks for disk creation *or* an existing device
	usage 1>&2
	exit
elif [ "$blocks" -gt 0 ] && [ -n "$device" ]; then
	# Can't specify blocks for disk creation *and* an existing device 
	usage 1>&2
	exit
elif [ -n "$disk_dir" ] && [ -n "$device" ]; then
	# Can't specify a dir for disk creation and an existing device
	usage 1>&2
	exit
elif [ -z "$categories" ]; then
	# Lets not assume anything here
	usage 1>&2
	exit
elif ! $kernel && ! $userspace ; then
	# Must specify at least one of these
	usage 1>&2
	exit
elif [ ! -d "$lower_mnt" ] || [ ! -d "$upper_mnt" ]; then
	# A small attempt at making sure we're dealing with directories
	usage 1>&2
	exit
elif [ -n "$disk_dir" ] && [ ! -d "$disk_dir" ]; then
	# A small attempt at making sure we're dealing with a directory
	usage 1>&2
	exit
fi

export ETL_LFS=$lower_fs
export ETL_LMOUNT_SRC=$device
export ETL_LMOUNT_DST=$lower_mnt
export ETL_MOUNT_SRC=$lower_mnt
export ETL_MOUNT_DST=$upper_mnt

if [ "$blocks" -gt 0 ]; then
	etl_create_disk $blocks $disk_dir
	if [ $? -ne 0 ]; then
		rc=1
		exit
	fi
	export ETL_LMOUNT_SRC=$ETL_DISK
fi

# Source in the kernel and/or userspace tests.rc files to build the test lists
categories=$(echo $categories | tr ',' ' ')
if $kernel ; then
	. ${run_tests_dir}/kernel/tests.rc
	for cat in $categories ; do
		eval cat_tests=\$$cat
		ktests="$ktests $cat_tests"
	done

	run_tests "${run_tests_dir}/kernel" "$ktests"
	if [ $? -ne 0 ]; then
		rc=1
		exit
	fi
fi
if $userspace ; then
	. ${run_tests_dir}/userspace/tests.rc
	for cat in $categories ; do
		eval cat_tests=\$$cat
		utests="$utests $cat_tests"
	done

	run_tests "${run_tests_dir}/userspace" "$utests"
	if [ $? -ne 0 ]; then
		rc=1
		exit
	fi
fi

rc=0
exit
