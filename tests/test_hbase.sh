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
export HBASE_VERSIONS="${@:-${HBASE_VERSIONS:-latest 1.0 1.1 1.2}}"

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST
export HBASE_STARGATE_PORT=8080
export HBASE_THRIFT_PORT=9090
export ZOOKEEPER_PORT=2181
export HBASE_PORTS="$ZOOKEEPER_PORT $HBASE_STARGATE_PORT 8085 $HBASE_THRIFT_PORT 9095 16000 16010 16201 16301"

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

startupwait 50

test_hbase(){
    local version="$1"
    hr
    echo "Setting up HBase $version test container"
    hr
    local DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $HBASE_PORTS
    when_ports_available $startupwait $HBASE_HOST $HBASE_PORTS
    echo "setting up test tables"
    local uniq_val=$(< /dev/urandom tr -dc 'a-zA-Z0-9' | head -c32 || :)
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<EOF
export JAVA_HOME=/usr
/hbase/bin/hbase shell <<EOF2
create 't1', 'cf1', { 'REGION_REPLICATION' => 1 }
create 'EmptyTable', 'cf2', { 'REGION_REPLICATION' => 1 }
create 'DisabledTable', 'cf3', { 'REGION_REPLICATION' => 1 }
disable 'DisabledTable'
put 't1', 'r1', 'cf1:q1', '$uniq_val'
put 't1', 'r2', 'cf1:q2', 'test'
put 't1', 'r3', 'cf1:q3', '5'
list
EOF2
hbase hbck &>/tmp/hbck.log
EOF
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    ./check_hbase_master_version.py       -e "$version"
    ./check_hbase_regionserver_version.py -e "$version" -P 16301
    hr
    ./check_hbase_hbck.py -f tests/data/hbck.log -a 0
    hr
    set +e
    ./check_hbase_hbck.py -f tests/data/hbck.log -a 3
    check_exit_code 1
    set -e
    hr
    set +e
    ./check_hbase_hbck.py -f tests/data/hbck-inconsistencies.log -a 0
    check_exit_code 2
    set -e
    hr
    set +e
    ./check_hbase_hbck.py -f tests/data/hbck-inconsistencies.log -a 3
    check_exit_code 2
    set -e
    hr
    set +e
    ./check_hbase_hbck.py -f nonexistent_file
    check_exit_code 3
    set -e
    hr
    docker_exec check_hbase_hbck.py -f /tmp/hbck.log -a 30
    hr
    set +e
    docker_exec check_hbase_hbck.py -f /tmp/hbck.log -a 1
    check_exit_code 1
    set -e
# ============================================================================ #
    hr
    # Python plugins use env for -H $HBASE_HOST -P 16010
    ./check_hbase_table_enabled.py -T t1
    hr
    ./check_hbase_table_enabled.py -T EmptyTable
    hr
    set +e
    ./check_hbase_table_enabled.py -T DisabledTable
    check_exit_code 2
    set -e
    hr
    set +e
    ./check_hbase_table_enabled.py -T nonexistent_table
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_table.py -T t1
    hr
    ./check_hbase_table.py -T EmptyTable
    hr
    set +e
    ./check_hbase_table.py -T DisabledTable
    check_exit_code 2
    set -e
    hr
    set +e
    ./check_hbase_table.py -T nonexistent_table
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_table_regions.py -T t1
    hr
    ./check_hbase_table_regions.py -T EmptyTable
    hr
    # even though DisabledTable table is disabled, it still has assigned regions
    ./check_hbase_table_regions.py -T DisabledTable
    hr
    # Re-assignment happens too fast, can't catch
    # forcibly unassign region and re-test
    #region=$(echo "locate_region 'DisabledTable', 'key1'" | hbase shell | awk '/ENCODED/{print $4; exit}' | sed 's/,$//')
    #region=$(echo "locate_region 'DisabledTable', 'key1'" | hbase shell | grep ENCODED | sed 's/.*ENCODED[[:space:]]*=>[[:space:]]*//; s/[[:space:]]*,.*$//')
    #echo "Attempting to disable region '$region' to test failure scenario for unassigned region"
    #docker exec -ti "$DOCKER_CONTAINER" "hbase shell <<< \"unassign '$region'\""
    #set +e
    #./check_hbase_table_regions.py -T DisabledTable
    #check_exit_code 2
    #set -e
    #hr
    set +e
    ./check_hbase_table_regions.py -T nonexistent_table
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_table_compaction_in_progress.py -T t1
    hr
    ./check_hbase_table_compaction_in_progress.py -T EmptyTable
    hr
    ./check_hbase_table_compaction_in_progress.py -T DisabledTable
    hr
    set +e
    ./check_hbase_table_compaction_in_progress.py -T nonexistent_table
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_region_balance.py
    hr
    ./check_hbase_regions_stuck_in_transition.py
    hr
    ./check_hbase_num_regions_in_transition.py
    hr
    ./check_hbase_regionserver_compaction_in_progress.py -P 16301
    hr
    $perl -T ./check_hbase_regionservers.pl
    hr
    $perl -T ./check_hbase_regionservers_jsp.pl
    hr
    $perl -T ./check_hbase_cell.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
    hr
    ./check_hbase_cell.py -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
    hr
    $perl -T ./check_hbase_cell.pl -T t1 -R r2 -C cf1:q2 -e test
    hr
    ./check_hbase_cell.py -T t1 -R r2 -C cf1:q2 -e test
    hr
    $perl -T ./check_hbase_cell.pl -T t1 -R r3 -C cf1:q3 -e 5 -w 5 -c 10 -g -u ms
    hr
    ./check_hbase_cell.py -T t1 -R r3 -C cf1:q3 -e 5 -w 5 -c 10 -g -u ms
    hr
    set +e
    $perl -T ./check_hbase_cell.pl -T t1 -R r3 -C cf1:q3 -e 5 -w 4 -c 10
    check_exit_code 1
    hr
    ./check_hbase_cell.py -T t1 -R r3 -C cf1:q3 -e 5 -w 4 -c 10
    check_exit_code 1
    hr
    $perl -T ./check_hbase_cell.pl -T t1 -R r3 -C cf1:q3 -e 5 -w 4 -c 4
    check_exit_code 2
    hr
    ./check_hbase_cell.py -T t1 -R r3 -C cf1:q3 -e 5 -w 4 -c 4
    check_exit_code 2
    hr
    $perl -T ./check_hbase_cell.pl -T t1 -R r1 -C cf2:q1
    check_exit_code 2
    hr
    ./check_hbase_cell.py -T t1 -R r1 -C cf2:q1
    check_exit_code 2
    hr
    $perl -T ./check_hbase_cell.pl -T t1 -R r1 -C cf1:q100
    check_exit_code 2
    hr
    ./check_hbase_cell.py -T t1 -R r1 -C cf1:q100
    check_exit_code 2
    set +e
    hr
    $perl -T ./check_hbase_cell_stargate.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
    hr
    $perl -T ./check_hbase_cell_thrift.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
# ============================================================================ #
    hr
    $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P 16301 --bean Hadoop:service=HBase,name=RegionServer,sub=Server -m compactionQueueLength
    hr
    $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P 16301 --bean Hadoop:service=HBase,name=RegionServer,sub=Server --all-metrics
    hr
    $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P 16301 --all-metrics
    #hr
    # XXX: both cause 500 internal server error
    #$perl -T ./check_hadoop_metrics.pl -H $HBASE_HOST -P 16301 --all-metrics
    #$perl -T ./check_hadoop_metrics.pl -H $HBASE_HOST -P 16301 -m compactionQueueLength
    #hr

    # use newer Python version "check_hbase_table.py" for newer versions of HBase
    #$perl -T ./check_hbase_tables.pl
    #hr
    #$perl -T ./check_hbase_tables_thrift.pl
    #hr

    # TODO:
    #$perl -T ./check_hbase_tables_stargate.pl
    #hr
    #$perl -T ./check_hbase_tables_jsp.pl

    hr
    check_hbase_table_region_balance.py -T t1
    hr
    check_hbase_table_region_balance.py -T EmptyTable
    hr
    check_hbase_table_region_balance.py -T DisabledTable
    hr
    # all tables
    check_hbase_table_region_balance.py
    hr
    set +e
    check_hbase_table_region_balance.py --list-tables
    check_exit_code 3
    set -e
    hr

    # Use Docker hbase-dev, zookeeper will have been built
    if is_zookeeper_built; then
        # not present in newer versions of HBase
        #$perl -T ./check_hbase_unassigned_regions_znode.pl
        :
    else
        echo "ZooKeeper not built - skipping ZooKeeper checks"
    fi
    hr
    docker_exec check_hbase_table_rowcount.pl -T t1 --hbase-bin /hbase/bin/hbase -w 3:3 -c 3:3 -t 60
    hr
    docker_exec check_zookeeper_znode.pl -H localhost -P $ZOOKEEPER_PORT -z /hbase -v -n --child-znodes
    hr
    docker_exec check_zookeeper_child_znodes.pl -H localhost -P $ZOOKEEPER_PORT -z /hbase/rs -v -w 1:1 -c 1:1
    # only there on older versions of HBase
    hr
    #docker_exec check_hbase_unassigned_regions_znode.pl -H localhost
    hr

# ============================================================================ #
    echo "Forced Failure Scenarios:"
    echo "sending kill signal to RegionServer"
    docker exec -ti "$DOCKER_CONTAINER" pkill -f RegionServer
    echo "waiting 10 secs for RegionServer to go down"
    sleep 10
    hr
    set +e
    $perl -T ./check_hbase_regionservers.pl
    check_exit_code 2
    set -e
    hr
    set +e
    # should still exit critical as there are no remaining regionservers live
    $perl -T ./check_hbase_regionservers.pl -w 2 -c 2
    check_exit_code 2
    set -e
    hr
# ============================================================================ #
    set +e
    $perl -T ./check_hbase_regionservers_jsp.pl
    check_exit_code 2
    set -e
    hr
    set +e
    # should still exit critical as there are no remaining regionservers live
    $perl -T ./check_hbase_regionservers_jsp.pl -w 2 -c 2
    check_exit_code 2
    set -e
    hr
# ============================================================================ #
    # Thrift API will hang so these python plugins will self timeout after 10 secs with UNKNOWN when the sole RegionServer is down
    set +e
    ./check_hbase_table.py -T t1
    check_exit_code 3
    set -e
    hr
    set +e
    ./check_hbase_table_enabled.py -T t1
    check_exit_code 3
    set -e
    hr
    set +e
    ./check_hbase_table_regions.py -T DisabledTable
    check_exit_code 3
    set -e
    hr

    delete_container
    echo
}


for version in $(ci_sample $HBASE_VERSIONS); do
    test_hbase $version
done
echo "All HBase Tests Succeeded"
echo
