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
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "U n i x"

# $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
# shellcheck disable=SC2154
run "$perl" -T ./check_disk_write.pl -d .

# ============================================================================ #
tmpfile="$(mktemp /tmp/check_file_checksum.txt.XXXXXX)"
echo test > "$tmpfile"
run "$perl" -T ./check_file_checksum.pl -f "$tmpfile" -v -c '4e1243bd22c66e76c2ba9eddc1f91394e57f9f83'

run "$perl" -T ./check_file_checksum.pl -f "$tmpfile" -vn -a adler32

run "$perl" -T ./check_file_adler32.pl  -f "$tmpfile" -v -c '062801cb'

run "$perl" -T ./check_file_crc.pl      -f "$tmpfile" -v -c '3bb935c6'

run "$perl" -T ./check_file_md5.pl      -f "$tmpfile" -v -c 'd8e8fca2dc0f896fd7cb4cb0031ba249'

run "$perl" -T ./check_file_sha1.pl     -f "$tmpfile" -v --checksum '4e1243bd22c66e76c2ba9eddc1f91394e57f9f83'

run "$perl" -T ./check_file_sha256.pl   -f "$tmpfile" -v -c 'f2ca1bb6c7e907d06dafe4687e579fce76b37e4e93b7605022da52e6ccc26fd2'

run "$perl" -T ./check_file_sha512.pl   -f "$tmpfile" -v -c '0e3e75234abc68f4378a86b3f4b32a198ba301845b0cd6e50106e874345700cc6663a86c1ea125dc5e92be17c98f9a0f85ca9d5f595db2012f7cc3571945c123'

rm -vf "$tmpfile"
hr

# test real login against HP iLO or similar if local environment is configured for it
if [ -n "${SSH_HOST:-}" ] &&
   [ -n "${SSH_USER:-}" ] &&
   [ -n "${SSH_PASSWORD:-}" ]; then
    run "$perl" -T ./check_ssh_login.pl -H "$SSH_HOST" -u "$SSH_USER" -p "$SSH_PASSWORD"
    echo "testing via environment variables:"
    run "$perl" -T ./check_ssh_login.pl
fi

echo "check fails on non-existent user when SSH'ing localhost:"
run_fail 2 "$perl" -T ./check_ssh_login.pl -H localhost -u check_ssh_login_nagios_plugin_test -p test

set +e
localtime="$(readlink /etc/localtime | sed 's/.*zoneinfo\///')"
timezone="$(date +%Z)"
set -e
[ -z "$localtime" ] && localtime="$timezone"
set +eo pipefail
if ! run "$perl" -T ./check_timezone.pl --timezone "$localtime" --alternate "$timezone"; then
    hr
    echo "above time check failed, retrying in case of mismatch between timezone and file"
    timezone_file="$(find /usr/share/zoneinfo -type f print0 | xargs -0 md5sum | grep "$(md5sum /etc/localtime | awk '{print $1}')" | head -n1 | awk '{print $2}')"
    # Alpine doesn't have this by default - could 'apk add tzdata', otherwise just hack it back to /etc/localtime
    [ -n "$timezone_file" ] || timezone_file="/etc/localtime"
    # let the above shell pipeline fail and only set -e from here as the plugin will give better feedback if timezone_file is empty
    set -eo pipefail
    run "$perl" -T ./check_timezone.pl --timezone "$localtime" --alternate "$timezone" --zoneinfo-file "$timezone_file"
fi

# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count Unix tests"
echo
echo "All Unix tests passed successfully"
echo
echo
