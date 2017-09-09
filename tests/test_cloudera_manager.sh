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
#                        C l o u d e r a   M a n a g e r
# ============================================================================ #
"

export QUICKSTART_CLUSTER="Cloudera QuickStart"
export CM_PORT="${CM_PORT:-7180}"
export CM_USER="${CM_USER:-admin}"
export CM_PASSWORD="${CM_USER:-admin}"
export CM_CLUSTER="${CM_CLUSTER:-$QUICKSTART_CLUSTER}"
export CM_VERSION="${CM_VERSION:-.*}"

if [ -z "${CM_HOST:-}" ]; then
    echo "WARNING: \$CM_HOST not set, skipping Cloudera Manager checks"
    exit 0
fi

trap_debug_env

if which nc &>/dev/null && ! echo | nc -G 1 "$CM_HOST" $CM_PORT; then
    echo "WARNING: Cloudera Manager host $CM_HOST:$CM_PORT not up, skipping Cloudera Manager checks"
    exit 0
fi

if which curl &>/dev/null && ! curl -sL localhost:7180/cmf/login | grep -qi cloudera; then
    echo "WARNING: Cloudera Manager host $CM_HOST:$CM_PORT did not contain ambari in html, may be some other service bound to the port, skipping..."
    exit 0
fi

# QuickStart VM often has some broken stuff, we're testing the code works, not the cluster
[ "$CM_CLUSTER" = "$QUICKSTART_CLUSTER" ] && set +e

hr
echo "$perl -T check_cloudera_manager_version.pl -e \"$CM_VERSION\""
$perl -T check_cloudera_manager_version.pl -e "$CM_VERSION"
hr
echo "$perl -T check_cloudera_manager.pl --api-ping"
$perl -T check_cloudera_manager.pl --api-ping
hr
echo "$perl -T check_cloudera_manager.pl --list-clusters"
$perl -T check_cloudera_manager.pl --list-clusters
hr
echo "$perl -T check_cloudera_manager.pl --list-users"
$perl -T check_cloudera_manager.pl --list-users
hr
echo "$perl -T check_cloudera_manager.pl --list-hosts"
$perl -T check_cloudera_manager.pl --list-hosts
hr
echo "$perl -T check_cloudera_manager.pl --list-services"
$perl -T check_cloudera_manager.pl --list-services
hr
echo "$perl -T check_cloudera_manager_config_stale.pl --list-roles -S hdfs"
$perl -T check_cloudera_manager_config_stale.pl --list-roles -S hdfs
hr
echo "$perl -T check_cloudera_manager_cluster_version.pl"
$perl -T check_cloudera_manager_cluster_version.pl
hr
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

service="$(bash-tools/random_select.sh "$services")"

echo "Selected service: $service"

if [ -n "${DEBUG2:-}" ]; then
    export DEBUG="$DEBUG2"
fi

# ============================================================================ #

hr
echo "$perl -T check_cloudera_manager_config_stale.pl -S '$service'"
$perl -T check_cloudera_manager_config_stale.pl -S "$service"
hr
echo "$perl -T check_cloudera_manager_config_validation.pl -S '$service'"
$perl -T check_cloudera_manager_config_validation.pl -S "$service"
hr
echo "$perl -T check_cloudera_manager_health.pl -S '$service'"
$perl -T check_cloudera_manager_health.pl -S "$service"
hr
echo "$perl -T check_cloudera_manager_license.pl"
$perl -T check_cloudera_manager_license.pl
hr
echo "$perl -T check_cloudera_manager_metrics.pl -S '$service' -a"
$perl -T check_cloudera_manager_metrics.pl -S '$service' -a
hr
echo "$perl -T check_cloudera_manager_status.pl -S '$service'"
$perl -T check_cloudera_manager_status.pl -S "$service"
hr
echo
echo "All Cloudera Manager tests passed successfully"
untrap
echo
echo
