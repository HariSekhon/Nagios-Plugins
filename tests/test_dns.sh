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
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "D N S"

echo "determining local nameservers from /etc/resolv.conf"
echo "(this is more likely to succeed in environments that egress filter external DNS calls)"
echo
set +eo pipefail
nameservers="$(awk '/nameserver/{print $2}' /etc/resolv.conf | tr '\n' ',' | sed 's/,$//')"
set -eo pipefail
if [ -z "$nameservers" ]; then
    nameservers="4.2.2.1,4.2.2.2,4.2.2.3,4.2.2.4"
    echo "failed to determine nameservers, defaulting to: $nameservers"
else
    echo "nameservers: $nameservers"
fi
echo

hr
echo "A record resolve:"
# $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
# shellcheck disable=SC2154
run "$perl" -T ./check_dns.pl --server "$nameservers" --record google.com

echo "PTR record resolve:"
run "$perl" -T ./check_dns.pl --server "$nameservers" --record 4.2.2.1 --type PTR

echo "check giving same IP record without --type PTR returns 'unknown' exit code"
run_usage "$perl" -T ./check_dns.pl --server "$nameservers" --record 4.2.2.1

echo "randomizing servers:"
run "$perl" -T ./check_dns.pl --server "$nameservers" --record google.com --randomize-servers

echo "MX record resolve:"
run "$perl" -T ./check_dns.pl --server "$nameservers" --record google.com --type MX

run "$perl" -T ./check_dns.pl --server "$nameservers" --record google.com --type NS --randomize-servers

#run "$perl" -T ./check_dns.pl --server "$nameservers" --record telenor.rs --type TXT --expected-regex '.*spf.*|[A-Za-z0-9+]+==|google-site-verification=[A-Za-z0-9-]+'
run "$perl" -T ./check_dns.pl --server "$nameservers" --record telenor.rs --type TXT --expected-regex '.+'

if [ "$nameservers" = "4.2.2.1,4.2.2.2,4.2.2.3,4.2.2.4" ]; then
    echo "replacing default nameservers with their FQDNs to test the pre-resolve nameservers code path"
    nameservers="a.resolvers.level3.net,b.resolvers.level3.net,c.resolvers.level3.net,d.resolvers.level3.net"
    echo "nameservers: $nameservers"
    hr
fi
echo "A record resolve with FDQN dns servers requiring pre-resolving:"
run "$perl" -T ./check_dns.pl --server "$nameservers" --record google.com --randomize-servers

echo "MX record resolve with FQDN dns servers requiring pre-resolving:"
run "$perl" -T ./check_dns.pl --server "$nameservers" --record google.com --type MX

echo
# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count DNS tests"
echo
echo "All DNS tests completed successfully"
echo
echo
