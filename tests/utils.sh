#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
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
srcdir_nagios_plugins_utils="${srcdir:-}"
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
. "$srcdir/excluded.sh"

# shellcheck disable=SC1090
. "$srcdir/../bash-tools/lib/utils.sh"

# shellcheck disable=SC1090
. "$srcdir/../bash-tools/lib/docker.sh"

export COMPOSE_PROJECT_NAME="nagios-plugins"

export PROJECT="nagios-plugins"

check(){
    cmd=$1
    msg=$2
    if eval "$cmd"; then
        echo "SUCCESS: $msg"
    else
        echo "FAILED: $msg"
        exit 1
    fi
}

srcdir="$srcdir_nagios_plugins_utils"
