
set -e
export NI_QUIET=1
#export VERBOSE=1
trap 'set +x ; echo; echo; echo FAILURE'  EXIT
set -x


# Basic test 1: /bin and /usr should exist
./isolate.sh 'test -e /bin -a -e /usr'

# Basic test 2: /etc should not exist
./isolate.sh 'test ! -e /etc'

# test pwd
test "$(./isolate.sh 'pwd')" = "$PWD"

# Test mounting of directory locally
tmpdir=`mktemp -d --tmpdir isolate-test.XXXXXXX`
./isolate.sh -m ". $tmpdir" "touch $tmpdir/file1"
test -e $tmpdir/file1
rm -r $tmpdir

# Test read-only mounting of directory locally
tmpdir=`mktemp -d --tmpdir isolate-test.XXXXXXX`
./isolate.sh -m ". ro:$tmpdir" "! touch $tmpdir/file1"
test ! -e $tmpdir/file1
rm -r "$tmpdir"

# Test mounting of a file
tmpdir=`mktemp --tmpdir isolate-test.XXXXXXX`
./isolate.sh -m ". $tmpdir" "echo -n 123 > $tmpdir"
test 123 = "$(cat $tmpdir)"
rm -r "$tmpdir"

# Test mounting of a dir at a different path
tmpdir=`mktemp -d --tmpdir isolate-test.XXXXXXX`
./isolate.sh -m ". /tmp/x1=$tmpdir" "touch /tmp/x1/file1"
test -e "$tmpdir"/file1
rm -r "$tmpdir"

# Test replacing a file with null file
./isolate.sh -m ". /bin/tar=none" 'test $(stat --format=%s /bin/tar) = 0'

# Test replacing a directory with an empty directory
./isolate.sh -m ". /usr/sbin=none" 'test ! -e /usr/sbin/chroot'




set +x
echo
echo
echo SUCCESS
trap - EXIT
