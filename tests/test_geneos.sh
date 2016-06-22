#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-06-22 09:51:51 +0100 (Wed, 22 Jun 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                                  G e n e o s
# ============================================================================ #
"

# Try to make these local tests with no dependencies for simplicity

hr
./geneos_wrapper.py $perl -T $I_lib ./check_disk_write.pl -d .
hr
./geneos_wrapper.py $perl -T $I_lib ./check_git_branch_checkout.pl -d . -b "$(git branch | awk '/^*/{print $2}')"
hr
echo "Testing failure detection of wrong git branch"
./geneos_wrapper.py $perl -t $I_lib ./check_git_branch_checkout.pl -d . -b nonexistentbranch
hr
echo test > test.txt
./geneos_wrapper.py $perl -T $I_lib ./check_file_checksum.pl -f test.txt -v -c '4e1243bd22c66e76c2ba9eddc1f91394e57f9f83'
./geneos_wrapper.py $perl -T $I_lib ./check_file_checksum.pl -f test.txt -vn -a adler32
./geneos_wrapper.py $perl -T $I_lib ./check_file_adler32.pl  -f test.txt -v -c '062801cb'
./geneos_wrapper.py $perl -T $I_lib ./check_file_crc.pl      -f test.txt -v -c '3bb935c6'
./geneos_wrapper.py $perl -T $I_lib ./check_file_md5.pl      -f test.txt -v -c 'd8e8fca2dc0f896fd7cb4cb0031ba249'
./geneos_wrapper.py $perl -T $I_lib ./check_file_sha1.pl     -f test.txt -v --checksum '4e1243bd22c66e76c2ba9eddc1f91394e57f9f83'
./geneos_wrapper.py $perl -T $I_lib ./check_file_sha256.pl   -f test.txt -v -c 'f2ca1bb6c7e907d06dafe4687e579fce76b37e4e93b7605022da52e6ccc26fd2'
./geneos_wrapper.py $perl -T $I_lib ./check_file_sha512.pl   -f test.txt -v -c '0e3e75234abc68f4378a86b3f4b32a198ba301845b0cd6e50106e874345700cc6663a86c1ea125dc5e92be17c98f9a0f85ca9d5f595db2012f7cc3571945c123'
hr
./geneos_wrapper.py $perl -T $I_lib ./check_timezone.pl -T "$(readlink /etc/localtime | sed 's/.*zoneinfo\///')" -A "$(date +%Z)" -T "$(readlink /etc/localtime)"
hr
echo; echo
