#!/bin/bash

# This script sets up Linux namespaces to isolate a process from the
# rest of the system.  It works in three phases: each phase
# recursively invokes the same script, to do the next phase.  Phases
# communicate via environment variables.
#
# The phases are:
# 1. set up the new root and "unshare"
# 2. bind-mount things inside and chroot
# 3. final setup in environment like cd and run the given program.


VERBOSE=${VERBOSE:-}
test -n "$VERBOSE" && set -x   # Echo every command before running.
set -e                         # Fail on errors

# Debug helper: If VERBOSE is set, run the command
debug () {
    test -n "$VERBOSE" && eval "$@"
    return 0
}
debug echo original args: phase=$NI_PHASE "$@"

# Default options (only change here if you want global defaults
# changed)
export METHOD=${METHOD:-chroot}
# Things which should almost always be mounted
MNTDIRS_DEFAULT="ro:/bin ro:/usr ro:/lib ro:/lib64 /proc /dev/urandom"
NI_TMPFS_SIZE_DEFAULT=32M


# Phase 1: basic setup of the new namespace.
# Create the base directory.
if [ -z "$NI_PHASE" ] ; then
    # Parse arguments
    NI_NET_UNSHARE="--net" # default
    while true ; do
        debug echo ARG: "$1"
        case "$1" in
        -m|--mnt)
            MNTDIRS="$2"
            shift 2
            ;;
        -v)
            export VERBOSE=1
            shift
            ;;
        -b)
            export NI_BASEDIR="$2"
            shift 2
            ;;
        --no-net)
            export NI_NET_UNSHARE=""
            shift 1
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
        esac
    done

    # Arrange default arguments
    export MNTDIRS=${MNTDIRS:-.}
    export NI_MNTDIRS_ALL="$MNTDIRS_DEFAULT $MNTDIRS"
    # Original uid/gid for changing back to user - not implemented yet.
    export NI_OLDID=${NI_OLDID:-`id -u`:`id -g`}
    export NI_TMPFS_SIZE=${NI_TMPFS_SIZE:-$NI_TMPFS_SIZE_DEFAULT}

    # Make our tmpdir
    if [ -z "$NI_BASEDIR" ] ; then
        export NI_BASEDIR=`mktemp -d isolate.XXXXXXXX --tmpdir`
        # To do when shell closed.  -d means 'remote empty dir only'.
        trap 'rm -d "$NI_BASEDIR"' EXIT KILL INT TERM
    fi

    # Do the unshare.  Re-run this same script in phase 2.
    export NI_PHASE=2
    unshare --map-root-user --mount-proc \
            --user --pid --uts --ipc $NI_NET_UNSHARE --mount \
            --fork bash "$0" "$@"

    # Clean up via the "trap" above.

# Phase 2: Mount stuff and chroot into the tmpdir
elif [ "$NI_PHASE" = 2 ] ; then
    debug echo "BEGIN phase 2"
    debug whoami
    # Mount a tmpfs to be our new root.
    mount -t tmpfs -o size=$NI_TMPFS_SIZE tmpfs "$NI_BASEDIR"
    # Go through all directories and create the mount points.  First pass.
    for dir in $NI_MNTDIRS_ALL; do
        # If "ro:" prefix, bind-mount read only
	# If "rbind:" prefix, use --rbind which seems necessary when
	#   the mount point has other mount points under it
        # This syntax is probably a bashism
        [[ "$dir" = *ro*:* ]] && readonly="--read-only" || readonly=""
        [[ "$dir" = *rbind*:* ]] && bindtype="--rbind" || bindtype="--bind"
        # remove the "ro:" prefixes and so on.
        dir="${dir#*:}"
	# is it mountpoint=dirname?  If so, split it into mntpoint and tomount.
        if [[ "$dir" = *=* ]] ; then
            tomount="${dir#*=}"    # dir=tomount
            dir="${dir%%=*}"
	    # If tomount is "none", then remove this file.
	    if [ "$tomount" = "none" ] ; then
		if [ ! -d "$dir" ] ; then
		    # If a file: mount /dev/null on it
		    tomount="/dev/null"
		else
		    # If a directory: mount a tmpfs on it
		    bindtype="-t tmpfs"
		    tomount="tmpfs"
		fi
	    fi
        else
	    tomount="$dir"
	    mntpoint="$dir"
	fi
	# If not absolute path (starting with /), then expand using
	# realpath
        if [[ "$dir" != /* ]] ; then
            dir=`realpath "$dir"`
        fi
        # If it's a file, prepare touch an empty file (required for
        # bind mounting files)
        if [ -e "$tomount" -a ! -d "$tomount" ] ; then
            mkdir -p "$NI_BASEDIR/`dirname "$dir"`"
            test -e "$NI_BASEDIR/$dir" || touch "$NI_BASEDIR/$dir"
        else
            # If it's a directory, make the dir.
            mkdir -p "$NI_BASEDIR/$dir"
	fi
	# Do mount
        mount $bindtype $readonly "$tomount" "$NI_BASEDIR/$dir"
    done
    # Copy this isolate.sh script into the new base.
    #mount --bind "$0" "$NI_BASEDIR/isolate.sh"
    cp -p "$0" "$NI_BASEDIR/isolate.sh"
    # Make tmpdir inside the new root.
    mkdir -p "$NI_BASEDIR/tmp/"

    debug whoami
    debug ls -l "$NI_BASEDIR"

    # Chroot to our new root recursively run this same script in the next phase.
    export NI_PHASE=3
    export NI_OLDPWD=`realpath $PWD`
    # If chroot method
    if [ $METHOD = "chroot" ] ; then
        cd "$NI_BASEDIR"
        exec chroot "." "/isolate.sh" "$@"
    # Using pivot_root.  One comment I saw said this was more secure,
    # but I haven't verified this working yet.  I think it may not be
    # needed when using bind mounts like we have.
    else
        true #... something fancy using pivot_root?
    fi

# Phase 3.  Do setup in the chroot, such as change to our former pwd
# and run our command.
elif [  "$NI_PHASE" = 3 ] ; then
    debug echo "BEGIN phase 3"
    cd "$NI_OLDPWD"
    debug mount
    test -n "$NI_QUIET" || echo `whoami 2>/dev/null` in `pwd`
    # Run particular command that was originally given on the command
    # line and passed down through each phase.
    if [ "$#" -gt 0 ] ; then
        test -n "$NI_QUIET" || echo "running command $@"
        eval "$@"
    # No command given, so start a shell
    else
        "$SHELL"  # TODO: bash script so will always be bash...
    fi
fi
