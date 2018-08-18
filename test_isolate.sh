
set -e
export NI_QUIET=1
#export VERBOSE=1
trap 'set +x ; echo; echo; echo FAILURE'  EXIT
set -x

./isolate.sh 'test -e /bin -a -e /usr'

./isolate.sh 'test ! -e /etc'

# test pwd
test "$(./isolate.sh 'pwd')" = "$PWD"

# Test mounting of directory locally
tmpdir=`mktemp -d --tmpdir isolate-test.XXXXXXX`
./isolate.sh -v -m ". $tmpdir" "touch $tmpdir/file1"
test -e $tmpdir/file1
rm -r $tmpdir

# Test read-only mounting of directory locally
tmpdir=`mktemp -d --tmpdir isolate-test.XXXXXXX`
VERBOSE=1 ./isolate.sh -m ". ro:$tmpdir" "! touch $tmpdir/file1"
test ! -e $tmpdir/file1
rm -r "$tmpdir"




set +x
echo
echo
echo SUCCESS
trap - EXIT
