#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-06 12:12:15 +0100 (Fri, 06 May 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

is_travis && exit 0

echo "
# ============================================================================ #
#                                  A m b a r i
# ============================================================================ #
"

export SANDBOX_CLUSTER="Sandbox"
export AMBARI_PORT="${AMBARI_PORT:-8080}"
export AMBARI_USER="${AMBARI_USER:-admin}"
export AMBARI_PASSWORD="${AMBARI_PASSWORD:-admin}"
export AMBARI_CLUSTER="${AMBARI_CLUSTER:-$SANDBOX_CLUSTER}"

if [ -z "${AMBARI_HOST:-}" ]; then
    echo "WARNING: \$AMBARI_HOST not set, skipping Ambari checks"
    exit 0
fi

trap_debug_env

if which nc &>/dev/null && ! echo | nc -G 1 "$AMBARI_HOST" $AMBARI_PORT; then
    echo "WARNING: Ambari host $AMBARI_HOST:$AMBARI_PORT not up, skipping Ambari checks"
    exit 0
fi

if which curl &>/dev/null && ! curl -sL "$AMBARI_HOST:$AMBARI_PORT" | grep -qi ambari; then
    echo "WARNING: Ambari host $AMBARI_HOST:$AMBARI_PORT did not contain ambari in html, may be some other service bound to the port, skipping..."
    exit 0
fi

# Sandbox often has some broken stuff, we're testing the code works, not the cluster
[ "$AMBARI_CLUSTER" = "$SANDBOX_CLUSTER" ] && set +e
echo "testing Ambari server $AMBARI_HOST"
hr
echo "$perl -T check_ambari_cluster_alerts_host_summary.pl"
$perl -T check_ambari_cluster_alerts_host_summary.pl
check_exit_code 0 1 2
hr
echo "$perl -T check_ambari_cluster_alerts_summary.pl"
$perl -T check_ambari_cluster_alerts_summary.pl
check_exit_code 0 1 2
hr
echo "$perl -T check_ambari_cluster_health_report.pl"
$perl -T check_ambari_cluster_health_report.pl
check_exit_code 0 1 2
hr
echo "$perl -T check_ambari_cluster_kerberized.pl"
$perl -T check_ambari_cluster_kerberized.pl
check_exit_code 0 2
hr
echo "$perl -T check_ambari_cluster_service_config_compatible.pl"
$perl -T check_ambari_cluster_service_config_compatible.pl
check_exit_code 0 1 2
hr
echo "$perl -T check_ambari_cluster_total_hosts.pl"
$perl -T check_ambari_cluster_total_hosts.pl
check_exit_code 0 1 2
hr
echo "$perl -T check_ambari_cluster_version.pl"
$perl -T check_ambari_cluster_version.pl
check_exit_code 0 1 2
hr
echo "$perl -T check_ambari_config_stale.pl"
$perl -T check_ambari_config_stale.pl
check_exit_code 0 1 2
hr
echo "$perl -T check_ambari_nodes.pl"
$perl -T check_ambari_nodes.pl
check_exit_code 0 1 2
hr
echo "$perl -T check_ambari_services.pl"
$perl -T check_ambari_services.pl
check_exit_code 0 1 2
hr
echo
echo
