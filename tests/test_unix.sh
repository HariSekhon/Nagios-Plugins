#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-07 13:41:58 +0100 (Wed, 07 Oct 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                                   U n i x
# ============================================================================ #
"

$perl -T $I_lib ./check_ssl_cert.pl -H www.google.com -w 2 -c 1 -v
hr
echo test > test.txt
$perl -T $I_lib ./check_file_checksum.pl -f test.txt -v -c '4e1243bd22c66e76c2ba9eddc1f91394e57f9f83'
$perl -T $I_lib ./check_file_checksum.pl -f test.txt -vn -a adler32
$perl -T $I_lib ./check_file_adler32.pl  -f test.txt -v -c '062801cb'
$perl -T $I_lib ./check_file_crc.pl      -f test.txt -v -c '3bb935c6'
$perl -T $I_lib ./check_file_md5.pl      -f test.txt -v -c 'd8e8fca2dc0f896fd7cb4cb0031ba249'
$perl -T $I_lib ./check_file_sha1.pl     -f test.txt -v --checksum '4e1243bd22c66e76c2ba9eddc1f91394e57f9f83'
$perl -T $I_lib ./check_file_sha256.pl   -f test.txt -v -c 'f2ca1bb6c7e907d06dafe4687e579fce76b37e4e93b7605022da52e6ccc26fd2'
$perl -T $I_lib ./check_file_sha512.pl   -f test.txt -v -c '0e3e75234abc68f4378a86b3f4b32a198ba301845b0cd6e50106e874345700cc6663a86c1ea125dc5e92be17c98f9a0f85ca9d5f595db2012f7cc3571945c123'
rm -f test.txt
hr
echo; echo
