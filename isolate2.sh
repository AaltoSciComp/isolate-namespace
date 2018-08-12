#!/bin/bash

set -x
set -e

METHOD=chroot

# Phase 1: when first started.
# Create the basic directory and unshare into it.
if [ -z "$NI_PHASE" ] ; then
    MNTDIRS=${MNTDIRS:-.}
    # Things which should almost always be mounted
    MNTDIRS_ALL=${MNTDIRS_ALL:-"/bin /lib /etc /usr /lib64 /proc"}
    export MNTDIRS="$MNTDIRS_ALL $MNTDIRS"
    # Make our tmpdir
    export NI_BASEDIR=`mktemp -d isolate.XXXXXXXX --tmpdir`

    # Do the unshare
    export NI_PHASE=2
    unshare --user --map-root-user --mount-proc --pid --net --uts --fork \
	    bash "$0" "$@"

    # Clean up: change to "trap" later after ensuring that there won't
    # be files left here and no chance of deleting stuff on mail
    # filesystem.
    rm -d "$NI_BASEDIR"  # remote empty dir only...

# Phase 2: chroot into the tmpdir
elif [ "$NI_PHASE" = 2 ] ; then
    echo "BEGIN phase 2"
    whoami
    mount -t tmpfs -o size=10k tmpfs "$NI_BASEDIR"
    for dir in $MNTDIRS; do
	dir=`realpath "$dir"`
	mkdir -p "$NI_BASEDIR/$dir"
	mount --bind "$dir" "$NI_BASEDIR/$dir"
    done
    #mount --bind "$0" "$NI_BASEDIR/isolate.sh"
    cp -p "$0" "$NI_BASEDIR/isolate.sh"
    mkdir -p "$NI_BASEDIR/tmp/"

    export NI_PHASE=3
    export NI_OLDPWD=`realpath $PWD`

    whoami
    ls -l "$NI_BASEDIR"
    ls -l "$NI_BASEDIR/m/home/home0/04/darstr1/unix/tmp/"

    # If chroot method
    if [ $METHOD = "chroot" ] ; then
	chroot "$NI_BASEDIR" "/isolate.sh" "$@"
    # Using pivot_root.  One comment I saw said this was more secure,
    # but I haven't verified this working yet.
    else
	true #...
    fi

# Do any pre-setup in the dir
elif [  "$NI_PHASE" = 3 ] ; then
    echo "BEGIN phase 3"
    cd "$NI_OLDPWD"
    pwd
    whoami
    mount
    echo "running command $@"
    if [ -z "$@" ] ; then
	exec bash
    else
	eval "$@"
    fi
fi
