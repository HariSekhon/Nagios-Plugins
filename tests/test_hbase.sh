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

echo "
# ============================================================================ #
#                                   H B a s e
# ============================================================================ #
"

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST
echo "using docker address '$HBASE_HOST'"

export DOCKER_CONTAINER="nagios-plugins-hbase"

if ! which docker &>/dev/null; then
    echo 'WARNING: Docker not found, skipping HBase checks!!!'
    exit 0
fi

startupwait=30
[ -n "${TRAVIS:-}" ] && let startupwait+=20

hr
echo "Setting up HBASE test container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! is_docker_container_running "$DOCKER_CONTAINER"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker HBASE test container"
    # need tty for sudo which hbase-start.sh local uses while ssh'ing localhost
    docker run -d -t --name "$DOCKER_CONTAINER" \
        -p 2181:2181 \
        -p 8080:8080 \
        -p 8085:8085 \
        -p 9090:9090 \
        -p 9095:9095 \
        -p 16000:16000 \
        -p 16010:16010 \
        -p 16201:16201 \
        -p 16301:16301 \
        harisekhon/hbase-dev
    echo "waiting $startupwait seconds for HBASE to start up..."
    sleep $startupwait
else
    echo "Docker HBASE test container already running"
fi

# set up test table
# needs to pick up JAVA_HOME from shell
#docker exec -i "$DOCKER_CONTAINER" /bin/bash <<EOF
#/hbase/bin/hbase shell <<EOF2
#list
#EOF2
#EOF

hr
# TODO: add $HOST env support
$perl -T $I_lib ./check_hbase_regionservers.pl -H $HBASE_HOST -P 8080
hr
# TODO: enable no tables CRITICAL check, then create table then re-check
$perl -T $I_lib ./check_hbase_tables.pl || :
$perl -T $I_lib ./check_hbase_tables_thrift.pl || :
# XXX: needs updates
#$perl -T $I_lib ./check_hbase_tables_stargate.pl
#$perl -T $I_lib ./check_hbase_tables_jsp.pl
#hr
#$perl -T $I_lib 
#hr
#$perl -T $I_lib 
hr
if is_linux; then
    $perl -T $I_lib ./check_hbase_unassigned_regions_znode.pl
else
    echo "skipping ZooKeeper checks as not on Linux"
fi
hr
echo
if [ -z "${NODELETE:-}" ]; then
    echo -n "Deleting container "
    docker rm -f "$DOCKER_CONTAINER"
fi
echo; echo
