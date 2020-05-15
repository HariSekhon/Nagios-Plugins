#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: Thu Jun 2 12:38:36 2016 +0100
#  (forked from Makefile)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# Fix for Kafka dependency bug in NetAddr::IP::InetBase
#
# This now fails with permission denied even with sudo to root on Mac OSX Sierra due to System Integrity Protection:
#
# csrutil status
#
# would need to disable to edit system InetBase as documented here:
#
# https://developer.apple.com/library/content/documentation/Security/Conceptual/System_Integrity_Protection_Guide/ConfiguringSystemIntegrityProtection/ConfiguringSystemIntegrityProtection.html

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
#. "$srcdir/../bash-tools/lib/utils.sh"

sudo=""
[ $EUID = 0 ] || sudo=sudo

libfilepath="$(perl -MNetAddr::IP::InetBase -e 'print $INC{"NetAddr/IP/InetBase.pm"}')"

if ! grep -q 'use Socket' "$libfilepath"; then
    echo "Patching $libfilepath"
    echo "doesn't work on Mac any more even with sudo due to System Integrity Protection so ignoring any failures"
    $sudo sed -i.bak "s/use strict;/use strict; use Socket;/" "$libfilepath" || :
fi
