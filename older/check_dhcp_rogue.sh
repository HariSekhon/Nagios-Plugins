#!/usr/bin/env bash
#
#  Author: Hari Sekhon
#  Date: 2006-09-21 14:06:20 +0100 (Thu, 21 Sep 2006)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# This wrapper is a quick way of making sure that
# there are no rogue dhcp servers on the network -h

# I should really patch the C code and then make this wrapper
# obsolete -h

VERSION=0.2

# Standard Nagios exit codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

# Paths to search for check_dhcp
PLUGIN_PATHS="
/usr/lib64/nagios/plugins
/usr/lib/nagios/plugins
/usr/local/nagios/plugins
/usr/nagios/libexec
"

check_dhcp=""
for path in $PLUGIN_PATHS; do
    if [ -f "$path/check_dhcp" ]; then
        check_dhcp="$patch/check_dhcp"
        break
    fi
done
[ -n "$check_dhcp" ] || { echo "UNKNOWN: cannot find check_dhcp in known Nagios plugin paths"; exit $UNKNOWN; }

# Put here the number of DHCP servers that you have, if more offers are received
# than you have dhcp servers for, then you have a rogue DHCP server.
DHCP_SERVERS=1

output=`$check_dhcp $@`
result=$?

# This depends on the output of the check_dhcp plugin which shouldn't change often
OFFERS=`sed 's/.*Received //;s/\(.\)\+ .*/\1/' <<< "$output" `

# Make sure we have a numeric number of offers from the sed above
if [[ "$OFFERS" == [0-9] ]]; then
    # Test that the number of offers are not more than the number of DHCP servers
    # we have specified above in the DHCP_SERVERS variable. If there are more
    # and the result of the test was 0 (ie the check_dhcp plugin thinks that this
    # is ok) then change it by outputting a warning and forcing the result to
    # a warning state
    if [ "$OFFERS" -gt "$DHCP_SERVERS" -a "$result" == "$OK" ]; then
        result=$WARNING
        output="$output Possible ROGUE DHCP Server Present!"
    fi
fi

echo "$output"
exit $result
