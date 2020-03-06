#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-03-06 15:32:23 +0000 (Fri, 06 Mar 2020)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

sudo=""
[ $EUID -eq 0 ] || sudo=sudo

if [ "$(uname -s)" != Darwin ]; then
    echo "OS is not Mac, skipping nagios plugins libexec symlinking"
    exit 0
fi

for libexec in /usr/local/Cellar/nagios-plugins/*/libexec /usr/local/Cellar/monitoring-plugins/*/libexec; do
    if [ -d "$libexec" ] &&
     ! [ -e /usr/local/nagios/libexec ]; then
        echo "symlinking nagios libexec on Mac for plugins that use utils.pm"
        "$sudo" mkdir -pv /usr/local/nagios &&
        "$sudo" ln -sfv "$libexec" /usr/local/nagios/
    fi;
done
