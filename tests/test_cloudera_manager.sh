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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

is_travis && exit 0

section "C l o u d e r a   M a n a g e r"

export QUICKSTART_CLUSTER="Cloudera QuickStart"
export CM_PORT="${CM_PORT:-7180}"
export CM_USER="${CM_USER:-admin}"
export CM_PASSWORD="${CM_USER:-admin}"
export CM_CLUSTER="${CM_CLUSTER:-$QUICKSTART_CLUSTER}"
export CM_VERSION="${CM_VERSION:-.*}"
PROTOCOL="http"
if [ -n "${CM_SSL:-}" ]; then
    PROTOCOL="https"
    # TODO: SSL env var support in plugins and set here
fi

trap_debug_env cm

echo "checking connection refused tests first:"
echo
# $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
# shellcheck disable=SC2154
run_conn_refused "$perl" -T check_cloudera_manager_version.pl -e "$CM_VERSION"

run_conn_refused "$perl" -T check_cloudera_manager.pl --api-ping

run_conn_refused "$perl" -T check_cloudera_manager_config_stale.pl --list-roles -S hdfs

run_conn_refused "$perl" -T check_cloudera_manager_cluster_version.pl

run_conn_refused "$perl" -T check_cloudera_manager_config_stale.pl -S "hdfs"

run_conn_refused "$perl" -T check_cloudera_manager_config_validation.pl -S "hdfs"

run_conn_refused "$perl" -T check_cloudera_manager_health.pl -S "hdfs"

run_conn_refused "$perl" -T check_cloudera_manager_license.pl

run_conn_refused "$perl" -T check_cloudera_manager_metrics.pl -S "hdfs" -a

run_conn_refused "$perl" -T check_cloudera_manager_status.pl -S "hdfs"

echo

if [ -z "${CM_HOST:-}" ]; then
    echo "WARNING: \$CM_HOST not set, skipping real Cloudera Manager checks"
else
    if ! when_ports_available 5 "$CM_HOST" "$CM_PORT"; then
        echo "WARNING: Cloudera Manager host $CM_HOST:$CM_PORT not up, skipping Cloudera Manager checks"
        echo
        echo
        exit 0
    fi
    hr
    if ! when_url_content 5 "$PROTOCOL://$CM_HOST:$CM_PORT/cmf/login" Cloudera; then
        echo "WARNING: Cloudera Manager host $CM_HOST:$CM_PORT did not contain Cloudera in html, may be some other service bound to the port, skipping..."
        echo
        echo
        exit 0
    fi
    hr

    run "$perl" -T check_cloudera_manager_version.pl -e "$CM_VERSION"

    run "$perl" -T check_cloudera_manager.pl --api-ping

    run_fail 3 "$perl" -T check_cloudera_manager.pl --list-clusters

    run "$perl" -T check_cloudera_manager.pl --list-users

    run_fail 3 "$perl" -T check_cloudera_manager.pl --list-hosts

    run_fail 3 "$perl" -T check_cloudera_manager.pl --list-services

    run_fail 3 "$perl" -T check_cloudera_manager_config_stale.pl --list-roles -S hdfs

    run "$perl" -T check_cloudera_manager_cluster_version.pl

    run_fail 2 "$perl" -T check_cloudera_manager_cluster_version.pl --expected 'fail-version'

    echo

    # ============================================================================ #
    echo

    # messes up geting these variables right which impacts the runs of the plugins further down
    if [ -n "${DEBUG:-}" ]; then
        DEBUG2="$DEBUG"
        export DEBUG=""
    fi

    set +o pipefail

    services="$(./check_cloudera_manager_config_stale.pl --list-services | tail -n +3)"

    set -o pipefail

    echo "Services:

    $services
    "

    # hbase service will be disabled in Quickstart VM
    #service="$(bash-tools/random_select.sh "hdfs yarn hive zookeeper")"
    service="$(bash-tools/random_select.sh "$services")"

    echo "Selected service: $service"

    if [ -n "${DEBUG2:-}" ]; then
        export DEBUG="$DEBUG2"
    fi

    # ============================================================================ #

    hr
    run "$perl" -T check_cloudera_manager_config_stale.pl -S "$service"

    run "$perl" -T check_cloudera_manager_config_validation.pl -S "$service"

    if [ "$CM_CLUSTER" = "$QUICKSTART_CLUSTER" ]; then
        run_fail 2 "$perl" -T check_cloudera_manager_health.pl -S "$service"

        # do not WARN if license is trial, do not warn if license reverts to free
        run "$perl" -T check_cloudera_manager_license.pl --license-trial --license-free

        run_fail "0 2" "$perl" -T check_cloudera_manager_status.pl -S "$service"
    else
        run "$perl" -T check_cloudera_manager_health.pl -S "$service"

        run "$perl" -T check_cloudera_manager_license.pl

        run "$perl" -T check_cloudera_manager_status.pl -S "$service"
    fi

    run "$perl" -T check_cloudera_manager_metrics.pl -S "$service" -a

fi
echo
# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count Cloudera Manager tests"
echo
echo "All Cloudera Manager tests passed successfully"
untrap
echo
echo
