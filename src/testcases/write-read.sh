#!/bin/bash

error() {
	echo "ERROR: $@" 1>&2
}

DIR=$(cat $HOME/.ecryptfs/Private.mnt)
[ -d "$DIR" ] || error "Bad private directory"

md5sums=$(mktemp /tmp/ecryptfs_test_md5sums.XXXXXXXX)

# Generate a file of a specified size from urandom;
# Append the md5sum to a master list
random_file_of_size() {
	local bytes="$1"
	local f=$(mktemp /tmp/ecryptfs_test.XXXXXXXX)
	dd if=/dev/urandom of=$f bs=1 count=$bytes >/dev/null 2>&1
	md5sum $f >> $md5sums
	_RET=$f
}

ecryptfs-mount-private
base=1
n=7
count=10
fuzz=0
# File sizes from 1-byte to 10^n bytes
for i in $(seq 1 $n); do
	#count=$((1000000000/$base))
	for j in $(seq 1 $count); do
		# Fuzz the filesize to keep from landing on 4K boundries
		fuzz=0
		if [ $base -gt 4096 ]; then
			fuzz=$(rand -s $RANDOM -M 4096)
		else
			fuzz=$(rand -s $RANDOM -M $base)
		fi
		size=$((base+fuzz))
		#echo -n "$base[$j] - [$fuzz]: "
		random_file_of_size $size
		mv "$_RET" "$DIR"
	done
	base=$((base*10))
done
sed -i "s:/tmp/::" $md5sums
sync
while mount | grep -qs $DIR; do
	ecryptfs-umount-private
done
ecryptfs-mount-private
cd "$DIR"
md5sum -c $md5sums || error "Incorrect results"

# Clean up
awk '{print $2}' $md5sums | xargs -i rm -f "$DIR"/{}
rm -f $md5sums
