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

section "A m b a r i"

export SANDBOX_CLUSTER="Sandbox"
export AMBARI_PORT="${AMBARI_PORT:-8080}"
export AMBARI_USER="${AMBARI_USER:-admin}"
export AMBARI_PASSWORD="${AMBARI_PASSWORD:-admin}"
export AMBARI_CLUSTER="${AMBARI_CLUSTER:-$SANDBOX_CLUSTER}"

trap_debug_env ambari

echo "running connection refused tests first:"
echo
run_conn_refused $perl -T check_ambari_cluster_alerts_host_summary.pl
hr
run_conn_refused $perl -T check_ambari_cluster_alerts_summary.pl
hr
run_conn_refused $perl -T check_ambari_cluster_health_report.pl
hr
run_conn_refused $perl -T check_ambari_cluster_kerberized.pl
hr
run_conn_refused $perl -T check_ambari_cluster_service_config_compatible.pl
hr
run_conn_refused $perl -T check_ambari_cluster_total_hosts.pl
hr
run_conn_refused $perl -T check_ambari_cluster_version.pl
hr
run_conn_refused $perl -T check_ambari_config_stale.pl
hr
run_conn_refused $perl -T check_ambari_nodes.pl
hr
run_conn_refused $perl -T check_ambari_services.pl
hr

echo

if [ -z "${AMBARI_HOST:-}" ]; then
    echo "WARNING: \$AMBARI_HOST not set, skipping real Ambari checks"
else
    # should be available immediately if pre-running
    if ! when_ports_available 5 "$AMBARI_HOST" $AMBARI_PORT; then
        echo "WARNING: Ambari host $AMBARI_HOST:$AMBARI_PORT not up, skipping Ambari checks"
        echo
        echo
        untrap
        exit 0
    fi

    if ! when_url_content 5 "http://$AMBARI_HOST:$AMBARI_PORT/#/login" Ambari; then
        echo "WARNING: Ambari host $AMBARI_HOST:$AMBARI_PORT did not contain Ambari in html, may be some other service bound to the port, skipping..."
        echo
        echo
        untrap
        exit 0
    fi

    # Sandbox often has some broken stuff, we're testing the code works, not the cluster
    [ "$AMBARI_CLUSTER" = "$SANDBOX_CLUSTER" ] && set +e
    echo "testing Ambari server $AMBARI_HOST"
    hr
    run_fail "0 1 2" $perl -T check_ambari_cluster_alerts_host_summary.pl
    hr
    run_fail "0 1 2" $perl -T check_ambari_cluster_alerts_summary.pl
    hr
    run_fail "0 1 2" $perl -T check_ambari_cluster_health_report.pl
    hr
    run_fail "0 2" $perl -T check_ambari_cluster_kerberized.pl
    hr
    run_fail "0 2" $perl -T check_ambari_cluster_service_config_compatible.pl
    hr
    run $perl -T check_ambari_cluster_total_hosts.pl
    hr
    run $perl -T check_ambari_cluster_version.pl
    hr
    run_fail 2 $perl -T check_ambari_cluster_version.pl --expected 'fail-version'
    hr
    run_fail "0 1" $perl -T check_ambari_config_stale.pl
    hr
    run_fail "0 1 2" $perl -T check_ambari_nodes.pl
    hr
    run_fail "0 1 2" $perl -T check_ambari_services.pl
    hr
fi

echo
echo "Completed $run_count Ambari tests"
echo
echo "All Ambari tests completed successfully"
untrap
echo
echo
