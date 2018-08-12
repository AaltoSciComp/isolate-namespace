#!/bin/bash
MNTDIRS="bin lib etc usr lib64 proc"

set -x
BASEDIR="$1"
shift
PHASE=$1

DIR="$BASEDIR"/new

if [ "$PHASE" != "phase2" ] ; then
    mkdir -p "$BASEDIR"
    mkdir -p "$DIR"
    #unshare -m -r -U bash <<EOF
    unshare --user --map-root-user --mount-proc --pid --net --uts --fork bash "$0" "$BASEDIR" phase2 "$@"
    rm -d "$DIR" "$BASEDIR"
elif [ "$PHASE" = "phase2" ] ; then
    shift
    mount -t tmpfs -o size=10k tmpfs "$DIR"
    whoami
    for dir in $MNTDIRS; do
	mkdir -p "$DIR/$dir"
	mount --bind "/$dir" "$DIR/$dir"
    done

    # Basic method, using chroot
    #chroot $DIR $@

    # Using pivot_root.  One comment I saw said this was more secure,
    # but I haven't verified this working yet.
    mkdir -p "$BASEDIR/oldroot"
    cd "$DIR"
    pivot_root . ../oldroot
    pwd
    ls ..
    ls ../oldroot
    umount ../oldroot
    chroot . "$@"

fi
