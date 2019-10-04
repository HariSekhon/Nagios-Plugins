#!/usr/bin/env bash
#
#  Author: Hari Sekhon
#  Date: 2011-05-18 10:09:06 +0000 (Wed, 18 May 2011)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

srcdir=`dirname $0`

export PATH=$PATH:/usr/sbin:/usr/lib64/nagios/plugins:/usr/lib/nagios/plugins:/usr/nagios/libexec:/usr/local/nagios/libexec

if ! type -P send_nsca &>/dev/null; then
    echo "CRITICAL: send_nsca was not found in path"
    exit $CRITICAL
fi
send_nsca=`which send_nsca`
send_nsca_cfg="$srcdir/../send_nsca.cfg"

lib=lib_nagios.sh
. "$srcdir/$lib" || { echo "Lib Send NSCA: FAILED to source $lib"; exit 2; }

for x in "$send_nsca" "$send_nsca_cfg"; do
    [ -f "$x" ] || die "CRITICAL: $x cannot be found"
done

[ -x "$send_nsca" ] || die "CRITICAL: $send_nsca is not set executable!"
