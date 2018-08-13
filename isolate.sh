#!/bin/bash

VERBOSE=${VERBOSE:-}
test -n "$VERBOSE" && set -x
set -e

export METHOD=${METHOD:-chroot}

# If VERBOSE is set, run the command
debug () {
    test -n "$VERBOSE" && eval "$@"
    return 0
}

export NI_OLDID=${NI_OLDID:-`id -u`:0}

# Phase 1: basic setup of the new namespace.
# Create the base directory.
if [ -z "$NI_PHASE" ] ; then
    MNTDIRS=${MNTDIRS:-.}
    # Things which should almost always be mounted
    MNTDIRS_BASE=${MNTDIRS_BASE:-"ro:/bin ro:/lib ro:/etc ro:/usr ro:/lib64 /proc"}
    export MNTDIRS="$MNTDIRS_BASE $MNTDIRS"
    # Make our tmpdir
    if [ -z "$NI_BASEDIR" ] ; then
	export NI_BASEDIR=`mktemp -d isolate.XXXXXXXX --tmpdir`
	# -d means 'remote empty dir only'
	trap 'rm -d "$NI_BASEDIR"' EXIT KILL INT TERM
    fi

    # Do the unshare.  Re-run this same script in phase 2.
    export NI_PHASE=2
    unshare --map-root-user --mount-proc \
	    --user --pid --net --uts --ipc --mount \
	     --fork bash "$0" "$@"

    # Clean up via the "trap" above.

# Phase 2: Mount stuff and chroot into the tmpdir
elif [ "$NI_PHASE" = 2 ] ; then
    echo "BEGIN phase 2"
    debug whoami
    # Mount a tmpfs to be our new root.
    mount -t tmpfs -o size=10k tmpfs "$NI_BASEDIR"
    # First pass... create all directories (if mounted read-only this
    # will be a problem later)
    for dir in $MNTDIRS; do
	# remove a "ro:" prefix.
	dir="${dir#*:}"
	dir=`realpath "$dir"`
	mkdir -p "$NI_BASEDIR/$dir"
    done
    # Copy the isolate.sh script into the new base.
    #mount --bind "$0" "$NI_BASEDIR/isolate.sh"
    cp -p "$0" "$NI_BASEDIR/isolate.sh"
    mkdir -p "$NI_BASEDIR/tmp/"

    # Mount each dir in the basedir
    for dir in $MNTDIRS; do
	# If "ro:" prefix, bind-mount read only
	# This is probably a bashism
	[[ "$dir" = *ro*:* ]] && readonly="--read-only" || readonly=""
	[[ "$dir" = *rbind*:* ]] && bindtype="--rbind" || bindtype="--bind"
	# remove a "ro:" prefix.
	dir="${dir#*:}"
	dir=`realpath "$dir"`
	mount $bindtype $readonly "$dir" "$NI_BASEDIR/$dir"
    done

    debug whoami
    debug ls -l "$NI_BASEDIR"

    export NI_PHASE=3
    export NI_OLDPWD=`realpath $PWD`

    # If chroot method
    if [ $METHOD = "chroot" ] ; then
	cd "$NI_BASEDIR"
	chroot "." "/isolate.sh" "$@"
    # Using pivot_root.  One comment I saw said this was more secure,
    # but I haven't verified this working yet.
    else
	true #... something fancy using pivot_root?
    fi

# Phase 3.  Do setup in the chroot, such as change to our former pwd
# and run our command.
elif [  "$NI_PHASE" = 3 ] ; then
    echo "BEGIN phase 3"
    cd "$NI_OLDPWD"
    debug mount
    echo `whoami` in `pwd`
    echo "running command $@"
    if [ "$#" -gt 0 ] ; then
	eval "$@"
    else
	exec "$SHELL"  # TODO: bash script so will always be bash...
    fi
fi
