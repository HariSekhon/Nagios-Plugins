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

export HBASE_VERSIONS="${@:-${HBASE_VERSIONS:-latest 0.96 0.98 1.0 1.1 1.2}}"

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST
export HBASE_MASTER_PORT=16010
export HBASE_REGIONSERVER_PORT=16301
export HBASE_STARGATE_PORT=8080
export HBASE_THRIFT_PORT=9090
export ZOOKEEPER_PORT=2181
export HBASE_PORTS="$ZOOKEEPER_PORT $HBASE_STARGATE_PORT 8085 $HBASE_THRIFT_PORT 9095 16000 $HBASE_MASTER_PORT 16201 $HBASE_REGIONSERVER_PORT"

check_docker_available

export MNTDIR="/pl"

docker_exec(){
    # this doesn't allocate TTY properly, blessing module bails out
    #docker-compose exec "$DOCKER_SERVICE" /bin/bash <<-EOF
    docker exec -i "${COMPOSE_PROJECT_NAME:-docker}_${DOCKER_SERVICE}_1" /bin/bash <<-EOF
    export JAVA_HOME=/usr
    $MNTDIR/$@
EOF
}

startupwait 50

test_hbase(){
    local version="$1"
    section2 "Setting up HBase $version test container"
    local DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $HBASE_PORTS
    VERSION="$version" docker-compose up -d
    hbase_master_port="`docker-compose port "$DOCKER_SERVICE" "$HBASE_MASTER_PORT" | sed 's/.*://'`"
    hbase_regionserver_port="`docker-compose port "$DOCKER_SERVICE" "$HBASE_REGIONSERVER_PORT" | sed 's/.*://'`"
    hbase_stargate_port="`docker-compose port "$DOCKER_SERVICE" "$HBASE_STARGATE_PORT" | sed 's/.*://'`"
    hbase_thrift_port="`docker-compose port "$DOCKER_SERVICE" "$HBASE_THRIFT_PORT" | sed 's/.*://'`"
    zookeeper_port="`docker-compose port "$DOCKER_SERVICE" "$ZOOKEEPER_PORT" | sed 's/.*://'`"
    hbase_ports=`{ for x in $HBASE_PORTS; do docker-compose port "$DOCKER_SERVICE" "$x"; done; } | sed 's/.*://'`
    when_ports_available "$startupwait" "$HBASE_HOST" $hbase_ports
    echo "setting up test tables"
    # tr occasionally errors out due to weird input chars, base64 for safety, but still remove chars liek '+' which will ruin --expected regex
    local uniq_val=$(< /dev/urandom base64 | tr -dc 'a-zA-Z0-9' 2>/dev/null | head -c32 || :)
    # gets ValueError: file descriptor cannot be a negative integer (-1), -T should be the workaround but hangs
    #docker-compose exec -T "$DOCKER_SERVICE" /bin/bash <<-EOF
    docker exec -i "${COMPOSE_PROJECT_NAME:-docker}_${DOCKER_SERVICE}_1" /bin/bash <<-EOF
    export JAVA_HOME=/usr
    /hbase/bin/hbase shell <<-EOF2
        create 't1', 'cf1', { 'REGION_REPLICATION' => 1 }
        create 'EmptyTable', 'cf2', 'cf3', { 'REGION_REPLICATION' => 1 }
        create 'DisabledTable', 'cf4', { 'REGION_REPLICATION' => 1 }
        disable 'DisabledTable'
        put 't1', 'r1', 'cf1:q1', '$uniq_val'
        put 't1', 'r2', 'cf1:q1', 'test'
        put 't1', 'r3', 'cf1:q1', '5'
        list
EOF2
    hbase org.apache.hadoop.hbase.util.RegionSplitter UniformSplitTable UniformSplit -c 100 -f cf1
    hbase org.apache.hadoop.hbase.util.RegionSplitter HexStringSplitTable HexStringSplit -c 100 -f cf1
    hbase hbck &>/tmp/hbck.log
    exit
EOF
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    ./check_hbase_master_version.py       -P "$hbase_master_port"       -e "$version"
    hr
    ./check_hbase_regionserver_version.py -P "$hbase_regionserver_port" -e "$version"
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
    # Python plugins use env for -H $HBASE_HOST
    ./check_hbase_table_enabled.py -P "$hbase_thrift_port" -T t1
    hr
    ./check_hbase_table_enabled.py -P "$hbase_thrift_port" -T EmptyTable
    hr
    set +e
    ./check_hbase_table_enabled.py -P "$hbase_thrift_port" -T DisabledTable
    check_exit_code 2
    set -e
    hr
    set +e
    ./check_hbase_table_enabled.py -P "$hbase_thrift_port" -T nonexistent_table
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_table.py -P "$hbase_thrift_port" -T t1
    hr
    ./check_hbase_table.py -P "$hbase_thrift_port" -T EmptyTable
    hr
    set +e
    ./check_hbase_table.py -P "$hbase_thrift_port" -T DisabledTable
    check_exit_code 2
    set -e
    hr
    set +e
    ./check_hbase_table.py -P "$hbase_thrift_port" -T nonexistent_table
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_table_regions.py -P "$hbase_thrift_port" -T t1
    hr
    ./check_hbase_table_regions.py -P "$hbase_thrift_port" -T EmptyTable
    hr
    # even though DisabledTable table is disabled, it still has assigned regions
    ./check_hbase_table_regions.py -P "$hbase_thrift_port" -T DisabledTable
    hr
    # Re-assignment happens too fast, can't catch
    # forcibly unassign region and re-test
    #region=$(echo "locate_region 'DisabledTable', 'key1'" | hbase shell | awk '/ENCODED/{print $4; exit}' | sed 's/,$//')
    #region=$(echo "locate_region 'DisabledTable', 'key1'" | hbase shell | grep ENCODED | sed 's/.*ENCODED[[:space:]]*=>[[:space:]]*//; s/[[:space:]]*,.*$//')
    #echo "Attempting to disable region '$region' to test failure scenario for unassigned region"
    #docker exec -ti "$DOCKER_CONTAINER" "hbase shell <<< \"unassign '$region'\""
    #set +e
    #./check_hbase_table_regions.py -P "$hbase_thrift_port" -T DisabledTable
    #check_exit_code 2
    #set -e
    #hr
    set +e
    ./check_hbase_table_regions.py -P "$hbase_thrift_port" -T nonexistent_table
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_table_compaction_in_progress.py -P "$hbase_master_port" -T t1
    hr
    ./check_hbase_table_compaction_in_progress.py -P "$hbase_master_port" -T EmptyTable
    hr
    ./check_hbase_table_compaction_in_progress.py -P "$hbase_master_port" -T DisabledTable
    hr
    set +e
    ./check_hbase_table_compaction_in_progress.py -P "$hbase_master_port" -T nonexistent_table
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_region_balance.py -P "$hbase_master_port"
    hr
    ./check_hbase_regions_stuck_in_transition.py -P "$hbase_master_port"
    hr
    ./check_hbase_num_regions_in_transition.py -P "$hbase_master_port"
    hr
    ./check_hbase_regionserver_compaction_in_progress.py -P "$hbase_regionserver_port"
    hr
    $perl -T ./check_hbase_regionservers.pl -P "$hbase_stargate_port"
    hr
    $perl -T ./check_hbase_regionservers_jsp.pl -P "$hbase_master_port"
# ============================================================================ #
    for x in "$perl -T ./check_hbase_cell.pl -P $hbase_thrift_port" "./check_hbase_cell.py -P $hbase_thrift_port" "$perl -T ./check_hbase_cell_stargate.pl -P $hbase_stargate_port"; do
        hr
        eval $x -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
        hr
        eval $x -T t1 -R r2 -C cf1:q1 --expected test --precision 3
        hr
        eval $x -T t1 -R r3 -C cf1:q1 -e 5 -w 5 -c 10 -g -u ms
        hr
        set +e
        eval $x -T t1 -R r3 -C cf1:q1 -e 5 -w 4 -c 10
        check_exit_code 1
        hr
        eval $x -T t1 -R r3 -C cf1:q1 -e 5 -w 4 -c 4
        check_exit_code 2
        hr
        eval $x -T t1 -R nonExistentRow -C cf1:q1
        check_exit_code 2
        hr
        eval $x -T t1 -R r1 -C nonExistentCF:q1
        check_exit_code 2
        hr
        eval $x -T t1 -R r1 -C cf1:nonExistentQF
        check_exit_code 2
        hr
        eval $x -T NonExistentTable -R r1 -C cf1:q1
        check_exit_code 2
        hr
        eval $x -T DisabledTable -R r1 -C cf1:q1
        check_exit_code 2
        hr
        eval $x -T EmptyTable -R r1 -C cf1:q1
        check_exit_code 2
        set +e
    done
    hr
    # this is only a symlink to check_hbase_cell.pl so just check it's still there and working
    $perl -T ./check_hbase_cell_thrift.pl -P "$hbase_thrift_port" -T t1 -R r1 -C cf1:q1 -e "$uniq_val"

# ============================================================================ #
    hr
    ./check_hbase_write.py -P "$hbase_thrift_port" -T t1 -w 100 --precision 3
    hr
    # this will also be checked later by check_hbase_rowcount that it returns to zero rows, ie. delete succeeded
    ./check_hbase_write.py -P "$hbase_thrift_port" -T EmptyTable -w 100 --precision 3
    hr
    set +e
    ./check_hbase_write.py -P "$hbase_thrift_port" -T DisabledTable -t 2
    check_exit_code 2
    hr
    ./check_hbase_write.py -P "$hbase_thrift_port" -T NonExistentTable
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    ./check_hbase_write_spray.py -P "$hbase_thrift_port" -T t1 -w 100 --precision 3
    hr
    # this will also be checked later by check_hbase_rowcount that it returns to zero rows, ie. delete succeeded
    ./check_hbase_write_spray.py -P "$hbase_thrift_port" -T EmptyTable -w 100 --precision 3
    hr
    # write to 100 regions...
    ./check_hbase_write_spray.py -P "$hbase_thrift_port" -T HexStringSplitTable -w 100 --precision 3
    hr
    set +e
    ./check_hbase_write_spray.py -P "$hbase_thrift_port" -T DisabledTable -t 2
    check_exit_code 2
    hr
    ./check_hbase_write_spray.py -P "$hbase_thrift_port" -T NonExistentTable
    check_exit_code 2
    set -e
# ============================================================================ #
    hr
    $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P "$hbase_regionserver_port" --bean Hadoop:service=HBase,name=RegionServer,sub=Server -m compactionQueueLength
    hr
    $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P "$hbase_regionserver_port" --bean Hadoop:service=HBase,name=RegionServer,sub=Server --all-metrics | sed 's/|.*$//' # too long exceeds Travis CI max log length due to the 100 region HexStringSplitTable multiplying out the available metrics
    hr
    $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P "$hbase_regionserver_port" --all-metrics
    #hr
    # XXX: both cause 500 internal server error
    #$perl -T ./check_hadoop_metrics.pl -H $HBASE_HOST -P "$hbase_regionserver_port" --all-metrics
    #$perl -T ./check_hadoop_metrics.pl -H $HBASE_HOST -P "$hbase_regionserver_port" -m compactionQueueLength
    #hr

    # use newer Python version "check_hbase_table.py" for newer versions of HBase
    #$perl -T ./check_hbase_tables.pl -P "$hbase_thrift_port"
    #hr
    #$perl -T ./check_hbase_tables_thrift.pl -P "$hbase_thrift_port"
    #hr

    # TODO:
    #$perl -T ./check_hbase_tables_stargate.pl -P "$hbase_stargate_port"
    #hr
    #$perl -T ./check_hbase_tables_jsp.pl -P "$hbase_master_port"

    hr
    check_hbase_table_region_balance.py -P "$hbase_thrift_port" -T t1
    hr
    check_hbase_table_region_balance.py -P "$hbase_thrift_port" -T EmptyTable
    hr
    check_hbase_table_region_balance.py -P "$hbase_thrift_port" -T DisabledTable
    hr
    # all tables
    check_hbase_table_region_balance.py -P "$hbase_thrift_port"
    hr
    set +e
    check_hbase_table_region_balance.py -P "$hbase_thrift_port" --list-tables
    check_exit_code 3
    set -e
    hr

    # Use Docker hbase-dev, zookeeper will have been built
    if is_zookeeper_built; then
        # not present in newer versions of HBase
        #$perl -T ./check_hbase_unassigned_regions_znode.pl -P "$zookeeper_port"
        :
    else
        echo "ZooKeeper not built - skipping ZooKeeper checks"
    fi
    hr
    docker_exec check_hbase_table_rowcount.pl -T t1 --hbase-bin /hbase/bin/hbase -w 3:3 -c 3:3 -t 60
    hr
    # This also checks that check_hbase_write.py deleted correctly
    docker_exec check_hbase_table_rowcount.pl -T EmptyTable --hbase-bin /hbase/bin/hbase -w 0:0 -c 0:0 -t 30
    hr
    docker_exec check_zookeeper_znode.pl -H localhost -P $ZOOKEEPER_PORT -z /hbase -v -n --child-znodes
    hr
    docker_exec check_zookeeper_child_znodes.pl -H localhost -P $ZOOKEEPER_PORT -z /hbase/rs -v -w 1:1 -c 1:1
    # only there on older versions of HBase
    hr
    #docker_exec check_hbase_unassigned_regions_znode.pl -H localhost
    hr

# ============================================================================ #
    if [ -n "${NODELETE:-1}" ]; then
        echo
        return
    fi
    echo "Forced Failure Scenarios:"
    echo "sending kill signal to RegionServer"
    docker exec -ti "$DOCKER_CONTAINER" pkill -f RegionServer
    echo "waiting 10 secs for RegionServer to go down"
    sleep 10
    hr
    set +e
    $perl -T ./check_hbase_regionservers.pl -P "$hbase_stargate_port"
    check_exit_code 2
    set -e
    hr
    set +e
    # should still exit critical as there are no remaining regionservers live
    $perl -T ./check_hbase_regionservers.pl -P "$hbase_stargate_port" -w 2 -c 2
    check_exit_code 2
    set -e
    hr
# ============================================================================ #
    set +e
    $perl -T ./check_hbase_regionservers_jsp.pl -P "$hbase_master_port"
    check_exit_code 2
    set -e
    hr
    set +e
    # should still exit critical as there are no remaining regionservers live
    $perl -T ./check_hbase_regionservers_jsp.pl -P "$hbase_master_port" -w 2 -c 2
    check_exit_code 2
    set -e
    hr
# ============================================================================ #
    echo "Thrift API checks will hang so these python plugins will self timeout after 10 secs with UNKNOWN when the sole RegionServer is down"
    set +e
    ./check_hbase_table.py -P "$hbase_thrift_port" -T t1
    check_exit_code 3
    hr
    ./check_hbase_table_enabled.py -P "$hbase_thrift_port" -T t1
    check_exit_code 3
    hr
    ./check_hbase_table_regions.py -P "$hbase_thrift_port" -T DisabledTable
    check_exit_code 3
    hr
    ./check_hbase_cell.py -P "$hbase_thrift_port" -T t1 -R r1 -C cf1:q1
    check_exit_code 3
    set -e
    hr
    echo "sending kill signal to ThriftServer"
    docker-compose exec "$DOCKER_SERVICE" pkill -f ThriftServer
    echo "waiting 5 secs for ThriftServer to go down"
    sleep 5
    echo "Thrift API checks should now fail with exit code 2"
    set +e
    ./check_hbase_table.py -P "$hbase_thift_port" -T t1
    check_exit_code 2
    hr
    ./check_hbase_table_enabled.py -P "$hbase_thift_port" -T t1
    check_exit_code 2
    hr
    ./check_hbase_table_regions.py -P "$hbase_thift_port" -T DisabledTable
    check_exit_code 2
    hr
    ./check_hbase_cell.py -P "$hbase_thift_port" -T t1 -R r1 -C cf1:q1
    check_exit_code 2
    set -e

    #delete_container
    docker-compose down
    echo
}


for version in $(ci_sample $HBASE_VERSIONS); do
    test_hbase $version
done

if [ -z "${NOTESTS:-}" ]; then
    echo "All HBase Tests Succeeded"
fi
echo
