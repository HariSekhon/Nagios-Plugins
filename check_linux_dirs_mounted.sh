#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2019-02-08 12:19:31 +0000 (Fri, 08 Feb 2019)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

exec 2>&1

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

usage(){
    if [ -n "$*" ]; then
        echo "$@"
        echo
    fi
    cat <<EOF

Nagios Plugin to check directories given as arguments are mounted

The directories given must be the mount points and will be checked against /proc/mounts

Does not use the 'mount' command because this can be outdated mtab information

This will catch disks that fail to mount or are not currently mounted, which often causes applications to end up writing to and filling up the root filesystem

Tested on CentOS 7

usage: ${0##*/} <dir1> <dir2> ...

EOF
    exit "$UNKNOWN"
}

for x in $@; do
    case "$x" in
        -*) usage
            ;;
    esac
done

if [ "$(uname -s)" != "Linux" ]; then
    echo "UNKNOWN: this plugin only works on Linux"
    exit "$UNKNOWN"
fi

if [ -z "$*" ]; then
    usage "no directories given as arguments"
fi

for directory in $@; do
    # could collect these in an array and print them all out but this is just a quick check
    if ! grep -q "^[^[:space:]]\\+[[:space:]]\\+$directory[[:space:]]\\+" /proc/mounts; then
        echo "CRITICAL: directory '$directory' not mounted"
        exit "$CRITICAL"
    fi
done

echo "OK: all directories mounted"
exit "$OK"
