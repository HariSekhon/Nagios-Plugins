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

#export HBASE_VERSIONS="${1:-latest 0.96 0.98 1.0 1.1 1.2}"
# TODO: < 1.0 container versions don't work
#export HBASE_VERSIONS="${@:-0.98 0.96}"
export HBASE_VERSIONS="${@:-latest 1.0 1.1 1.2}"

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST
export HBASE_STARGATE_PORT=8080
#export HBASE_THRIFT_PORT=9090

export DOCKER_IMAGE="harisekhon/hbase-dev"
export DOCKER_CONTAINER="nagios-plugins-hbase-test"

export MNTDIR="/pl"

if ! is_docker_available; then
    echo "Docker not available, skipping HBase checks"
    exit 1
fi

docker_exec(){
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
    export JAVA_HOME=/usr
    $MNTDIR/$@
EOF
}

startupwait=50

test_hbase(){
    local version="$1"
    hr
    echo "Setting up HBase $version test container"
    hr
    local DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" 2181 8080 8085 9090 9095 16000 16010 16201 16301

    echo "setting up test tables"
    local uniq_val=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c32 || :)
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<EOF
export JAVA_HOME=/usr
/hbase/bin/hbase shell <<EOF2
create 't1', 'cf1', { 'REGION_REPLICATION' => 1 }
create 't2', 'cf2', { 'REGION_REPLICATION' => 1 }
disable 't2'
put 't1', 'r1', 'cf1:q1', '$uniq_val'
put 't1', 'r2', 'cf1:q2', 'test'
list
EOF2
EOF
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    hr
    # TODO: add $HOST env support
    $perl -T $I_lib ./check_hbase_regionservers.pl -H $HBASE_HOST -P 8080
    hr
    $perl -T $I_lib ./check_hbase_regionservers_jsp.pl -H $HBASE_HOST -P 16010
    hr
    $perl -T $I_lib ./check_hbase_cell.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
    hr
    $perl -T $I_lib ./check_hbase_cell_stargate.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
    hr
    $perl -T $I_lib ./check_hbase_cell_thrift.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
    hr
    $perl -T $I_lib ./check_hadoop_jmx.pl -H $HBASE_HOST -P 16301 --bean Hadoop:service=HBase,name=RegionServer,sub=Server -m compactionQueueLength
    hr
    $perl -T $I_lib ./check_hadoop_jmx.pl -H $HBASE_HOST -P 16301 --bean Hadoop:service=HBase,name=RegionServer,sub=Server --all-metrics
    hr
    $perl -T $I_lib ./check_hadoop_jmx.pl -H $HBASE_HOST -P 16301 --all-metrics
    hr
    # XXX: both cause 500 internal server error
    #$perl -T $I_lib ./check_hadoop_metrics.pl -H $HBASE_HOST -P 16301 --all-metrics
    #$perl -T $I_lib ./check_hadoop_metrics.pl -H $HBASE_HOST -P 16301 -m compactionQueueLength
    hr
    # TODO: need updates
    #$perl -T $I_lib ./check_hbase_tables.pl
    #$perl -T $I_lib ./check_hbase_tables_thrift.pl
    #$perl -T $I_lib ./check_hbase_tables_stargate.pl
    #$perl -T $I_lib ./check_hbase_tables_jsp.pl
    #hr
    hr
    # Use Docker hbase-dev, zookeeper will have been built
    #if is_zookeeper_built; then
    #    $perl -T $I_lib ./check_hbase_unassigned_regions_znode.pl
    #    hr
    #else
    #    echo "ZooKeeper not built - skipping ZooKeeper checks"
    #fi
    docker_exec check_hbase_table_rowcount.pl -T t1 --hbase-bin /hbase/bin/hbase -w 2 -c 2 -t 60
    hr
    docker_exec check_zookeeper_znode.pl -H localhost -P 2181 -z /hbase -v -n --child-znodes
    hr
    docker_exec check_zookeeper_child_znodes.pl -H localhost -P 2181 -z /hbase/rs -v -w 1:1 -c 1:1
    # only there on older versions of HBase
    #hr
    #docker_exec check_hbase_unassigned_regions_znode.pl -H localhost
    hr

    delete_container
    echo
}


for version in $(ci_sample $HBASE_VERSIONS); do
    test_hbase $version
done
