#!/bin/bash

VERBOSE=${VERBOSE:-}
test -n "$VERBOSE" && set -x
set -e

# If VERBOSE is set, run the command
debug () {
    test -n "$VERBOSE" && eval "$@"
    return 0
}


debug echo original args: phase=$NI_PHASE "$@"

export METHOD=${METHOD:-chroot}
# Things which should almost always be mounted
MNTDIRS_DEFAULT="ro:/bin ro:/usr ro:/lib ro:/lib64 /proc ro:/etc rbind:/dev"


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




    # Make our tmpdir
    if [ -z "$NI_BASEDIR" ] ; then
        export NI_BASEDIR=`mktemp -d isolate.XXXXXXXX --tmpdir`
        # -d means 'remote empty dir only'
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
    echo "BEGIN phase 2"
    debug whoami
    # Mount a tmpfs to be our new root.
    mount -t tmpfs -o size=10k tmpfs "$NI_BASEDIR"
    # First pass... create all directories (if mounted read-only this
    # will be a problem later)
    for dir in $NI_MNTDIRS_ALL; do
        # remove a "ro:" prefix.
        dir="${dir#*:}"
        if [[ "$dir" != /* ]] ; then
            dir=`realpath "$dir"`
        fi
        # If it's a file, prepare to bind mount the file
        if [ -e "$dir" -a ! -d "$dir" ] ; then
            mkdir -p "$NI_BASEDIR`dirname "$dir"`"
            touch "$NI_BASEDIR/$dir"
            continue
        fi
        # directory - make the dir
        mkdir -p "$NI_BASEDIR/$dir"
    done
    # Copy the isolate.sh script into the new base.
    #mount --bind "$0" "$NI_BASEDIR/isolate.sh"
    cp -p "$0" "$NI_BASEDIR/isolate.sh"
    mkdir -p "$NI_BASEDIR/tmp/"

    # Mount each dir in the basedir
    for dir in $NI_MNTDIRS_ALL; do
        # If "ro:" prefix, bind-mount read only
        # This is probably a bashism
        [[ "$dir" = *ro*:* ]] && readonly="--read-only" || readonly=""
        [[ "$dir" = *rbind*:* ]] && bindtype="--rbind" || bindtype="--bind"
        # remove a "ro:" prefix.
        dir="${dir#*:}"
        # If does not begin with "/", then
        if [[ "$dir" != /* ]] ; then
            dir=`realpath "$dir"`
        fi
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
    if [ "$#" -gt 0 ] ; then
        echo "running command $@"
        eval "$@"
    else
        exec "$SHELL"  # TODO: bash script so will always be bash...
    fi
fi
