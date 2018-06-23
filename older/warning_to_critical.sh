#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-06-21 12:41:59 +0100 (Thu, 21 Jun 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -u
[ -n "${DEBUG:-}" ] && set -x

usage(){
    echo "
Upgrades a Nagios Plugin's status to CRITICAL if WARNING is returned

usage: ${0##*/} <nagios_plugin> <args>
"
    exit 3
}

for x in $@; do
    case $x in
         -h|--help) usage ;;
    esac
done

output="$($@ 2>&1)"
result=$?
if [ $result -eq 1 ]; then
    sed 's/^WARNING:/CRITICAL:/' <<< "$output"
    exit 2
fi
echo "$output"
exit $result
