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

srcdir2="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir2/.."

. "$srcdir2/utils.sh"

srcdir="$srcdir2"

echo "
# ============================================================================ #
#                                   H B a s e
# ============================================================================ #
"

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST
export HBASE_STARGATE_PORT=8080
#export HBASE_THRIFT_PORT=9090

export DOCKER_IMAGE="harisekhon/hbase-dev"
export DOCKER_CONTAINER="nagios-plugins-hbase-test"

startupwait=45

hr
echo "Setting up HBase test container"
hr
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" 2181 8080 8085 9090 9095 16000 16010 16201 16301

echo "setting up test tables"
uniq_val=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n1 || :)
docker exec -i "$DOCKER_CONTAINER" /bin/bash <<EOF
export JAVA_HOME=/usr
/hbase/bin/hbase shell <<EOF2
create 't1', 'cf1', { REGION_REPLICATION => 1 }
create 't2', 'cf2', { REGION_REPLICATION => 1 }
disable 't2'
put 't1', 'r1', 'cf1:q1', '$uniq_val'
put 't1', 'r2', 'cf1:q2', 'test'
list
EOF2
EOF

hr
# TODO: add $HOST env support
$perl -T $I_lib ./check_hbase_regionservers.pl -H $HBASE_HOST -P 8080
hr
$perl -T $I_lib ./check_hbase_cell.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
hr
$perl -T $I_lib ./check_hbase_cell_stargate.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
hr
$perl -T $I_lib ./check_hbase_cell_thrift.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
hr
# TODO: need updates
#$perl -T $I_lib ./check_hbase_tables.pl
#$perl -T $I_lib ./check_hbase_tables_thrift.pl
#$perl -T $I_lib ./check_hbase_tables_stargate.pl
#$perl -T $I_lib ./check_hbase_tables_jsp.pl
#hr
#$perl -T $I_lib 
#hr
#$perl -T $I_lib 
hr
# Use Docker hbase-dev, zookeeper will have been built
#if is_zookeeper_built; then
#    $perl -T $I_lib ./check_hbase_unassigned_regions_znode.pl
#    hr
#else
#    echo "ZooKeeper not built - skipping ZooKeeper checks"
#fi
docker exec -ti "$DOCKER_CONTAINER" -v "$srcdir/..":/pl /pl/check_hbase_unassigned_regions_znode.pl -H localhost
hr

delete_container
