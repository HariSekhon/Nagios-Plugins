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

section "H B a s e"

export HBASE_VERSIONS="${@:-${HBASE_VERSIONS:-latest 0.96 0.98 1.0 1.1 1.2}}"

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST
export HBASE_MASTER_PORT_DEFAULT=16010
export HBASE_REGIONSERVER_PORT_DEFAULT=16301
export HBASE_STARGATE_PORT_DEFAULT=8080
export HBASE_THRIFT_PORT_DEFAULT=9090
export ZOOKEEPER_PORT_DEFAULT=2181

check_docker_available

trap_debug_env hbase

export MNTDIR="/pl"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-docker}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME//-}"

docker_exec(){
    # this doesn't allocate TTY properly, blessing module bails out
    #docker-compose exec "$DOCKER_SERVICE" /bin/bash <<-EOF
    echo "docker exec -i '${COMPOSE_PROJECT_NAME}_${DOCKER_SERVICE}_1' /bin/bash <<-EOF
    export JAVA_HOME=/usr
    $MNTDIR/$@
EOF"
    # TODO: check if this can output the here doc and if so remove above echo
    run docker exec -i "${COMPOSE_PROJECT_NAME}_${DOCKER_SERVICE}_1" /bin/bash <<-EOF
    export JAVA_HOME=/usr
    $MNTDIR/$@
EOF
}

startupwait 15

test_hbase(){
    local version="$1"
    section2 "Setting up HBase $version test container"
    # we kill RegionServer and Thrift server near the end to test failure scenarios so do not re-use these containers
    if [ -z "${KEEPDOCKER:-}" ]; then
        docker-compose down || :
    fi
    VERSION="$version" docker-compose up -d
    if [ "$version" = "0.96" -o "$version" = "0.98" ]; then
        local export HBASE_MASTER_PORT_DEFAULT=60010
        local export HBASE_REGIONSERVER_PORT_DEFAULT=60301
    fi
    echo "getting HBase dynamic port mappings"
    printf "getting HBase Master port       => "
    export HBASE_MASTER_PORT="`docker-compose port "$DOCKER_SERVICE" "$HBASE_MASTER_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$HBASE_MASTER_PORT"
    printf "getting HBase RegionServer port => "
    export HBASE_REGIONSERVER_PORT="`docker-compose port "$DOCKER_SERVICE" "$HBASE_REGIONSERVER_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$HBASE_REGIONSERVER_PORT"
    printf "getting HBase Stargate port     => "
    export HBASE_STARGATE_PORT="`docker-compose port "$DOCKER_SERVICE" "$HBASE_STARGATE_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$HBASE_STARGATE_PORT"
    printf "getting HBase Thrift port       => "
    export HBASE_THRIFT_PORT="`docker-compose port "$DOCKER_SERVICE" "$HBASE_THRIFT_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$HBASE_THRIFT_PORT"
    printf "getting HBase ZooKeeper port    => "
    export ZOOKEEPER_PORT="`docker-compose port "$DOCKER_SERVICE" "$ZOOKEEPER_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$ZOOKEEPER_PORT"
    #local export HBASE_PORTS=`{ for x in $HBASE_PORTS; do docker-compose port "$DOCKER_SERVICE" "$x"; done; } | sed 's/.*://' | sort -n`
    export HBASE_PORTS="$HBASE_MASTER_PORT $HBASE_REGIONSERVER_PORT $HBASE_STARGATE_PORT $HBASE_THRIFT_PORT $ZOOKEEPER_PORT"
    when_ports_available "$startupwait" "$HBASE_HOST" $HBASE_PORTS
    hr
    when_url_content "$startupwait" "http://$HBASE_HOST:$HBASE_MASTER_PORT/master-status" hbase
    hr
    when_url_content "$startupwait" "http://$HBASE_HOST:$HBASE_REGIONSERVER_PORT/rs-status" hbase
    hr
    echo "setting up test tables"
    # tr occasionally errors out due to weird input chars, base64 for safety, but still remove chars liek '+' which will ruin --expected regex
    local uniq_val=$(< /dev/urandom base64 | tr -dc 'a-zA-Z0-9' 2>/dev/null | head -c32 || :)
    # gets ValueError: file descriptor cannot be a negative integer (-1), -T should be the workaround but hangs
    #docker-compose exec -T "$DOCKER_SERVICE" /bin/bash <<-EOF
    local DOCKER_CONTAINER="${COMPOSE_PROJECT_NAME}_${DOCKER_SERVICE}_1"
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
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
    echo "creating hbck.log"
    hbase hbck &>/tmp/hbck.log
    echo "test setup finished"
    exit
EOF
    #docker cp "${COMPOSE_PROJECT_NAME}_${DOCKER_SERVICE}_1":/tmp/hbck.log tests/data/hbase-hbck-$version.log
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    echo "starting tests for version $version"
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    run ./check_hbase_master_version.py -e "$version"
    hr
    run ./check_hbase_regionserver_version.py -e "$version"
    hr
    run ./check_hbase_hbck.py -f tests/data/hbck.log -a 0
    hr
    run_fail 1 ./check_hbase_hbck.py -f tests/data/hbck.log -a 3
    hr
    docker_exec check_hbase_hbck.py -f /tmp/hbck.log -a 30
    hr
    set +e
    docker_exec check_hbase_hbck.py -f /tmp/hbck.log -a 1
    check_exit_code 1
    set -e
    hr
    run_fail 2 ./check_hbase_hbck.py -f tests/data/hbck-inconsistencies.log -a 0
    hr
    run_fail 2 ./check_hbase_hbck.py -f tests/data/hbck-inconsistencies.log -a 3
    hr
    run_fail 3 ./check_hbase_hbck.py -f nonexistent_file
# ============================================================================ #
    hr
    # Python plugins use env for -H $HBASE_HOST
    run ./check_hbase_table_enabled.py -T t1
    hr
    run ./check_hbase_table_enabled.py -T EmptyTable
    hr
    run_fail 2 ./check_hbase_table_enabled.py -T DisabledTable
    hr
    set +e
    # TODO: this used to work I'm sure but now it's behaviour is completely broken is now returning OK on multiple HBase versions
    run_fail "0 2" ./check_hbase_table_enabled.py -T nonexistent_table
# ============================================================================ #
    hr
    run ./check_hbase_table.py -T t1
    hr
    run ./check_hbase_table.py -T EmptyTable
    hr
    run_fail 2 ./check_hbase_table.py -T DisabledTable
    hr
    run_fail 2 ./check_hbase_table.py -T nonexistent_table
# ============================================================================ #
    hr
    run ./check_hbase_table_regions.py -T t1
    hr
    run ./check_hbase_table_regions.py -T EmptyTable
    hr
    # even though DisabledTable table is disabled, it still has assigned regions
    run ./check_hbase_table_regions.py -T DisabledTable
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
    run_fail 2 ./check_hbase_table_regions.py -T nonexistent_table
# ============================================================================ #
    hr
    run ./check_hbase_table_compaction_in_progress.py -T t1
    hr
    run ./check_hbase_table_compaction_in_progress.py -T EmptyTable
    hr
    run ./check_hbase_table_compaction_in_progress.py -T DisabledTable
    hr
    run_fail 2 ./check_hbase_table_compaction_in_progress.py -T nonexistent_table
# ============================================================================ #
    hr
    run ./check_hbase_region_balance.py
    hr
    run ./check_hbase_regions_stuck_in_transition.py
    hr
    run ./check_hbase_num_regions_in_transition.py
    hr
    run ./check_hbase_regionserver_compaction_in_progress.py
    hr
    echo "ensuring Stargate Server is properly online before running this test"
    when_url_content "$startupwait" "http://$HBASE_HOST:$HBASE_STARGATE_PORT/" UniformSplitTable
    hr
    run $perl -T ./check_hbase_regionservers.pl
    hr
    run $perl -T ./check_hbase_regionservers_jsp.pl
# ============================================================================ #
    for x in "$perl -T ./check_hbase_cell.pl" ./check_hbase_cell.py "$perl -T ./check_hbase_cell_stargate.pl"; do
        hr
        run eval $x -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
        hr
        run eval $x -T t1 -R r2 -C cf1:q1 --expected test --precision 3
        hr
        run eval $x -T t1 -R r3 -C cf1:q1 -e 5 -w 5 -c 10 -g -u ms
        hr
        run_fail 1 eval $x -T t1 -R r3 -C cf1:q1 -e 5 -w 4 -c 10
        hr
        run_fail 2 eval $x -T t1 -R r3 -C cf1:q1 -e 5 -w 4 -c 4
        hr
        run_fail 2 eval $x -T t1 -R nonExistentRow -C cf1:q1
        hr
        run_fail 2 eval $x -T t1 -R r1 -C nonExistentCF:q1
        hr
        run_fail 2 eval $x -T t1 -R r1 -C cf1:nonExistentQF
        hr
        run_fail 2 eval $x -T NonExistentTable -R r1 -C cf1:q1
        hr
        run_fail 2 eval $x -T DisabledTable -R r1 -C cf1:q1
        hr
        run_fail 2 eval $x -T EmptyTable -R r1 -C cf1:q1
    done
    hr
    # this is only a symlink to check_hbase_cell.pl so just check it's still there and working
    run $perl -T ./check_hbase_cell_thrift.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"

# ============================================================================ #
    hr
    run ./check_hbase_write.py -T t1 -w 100 --precision 3
    hr
    # this will also be checked later by check_hbase_rowcount that it returns to zero rows, ie. delete succeeded
    run ./check_hbase_write.py -T EmptyTable -w 100 --precision 3
    hr
    run_fail 2 ./check_hbase_write.py -T DisabledTable -t 2
    hr
    run_fail 2 ./check_hbase_write.py -T NonExistentTable
# ============================================================================ #
    hr
    run ./check_hbase_write_spray.py -T t1 -w 500 --precision 3 -t 20
    hr
    # this will also be checked later by check_hbase_rowcount that it returns to zero rows, ie. delete succeeded
    run ./check_hbase_write_spray.py -T EmptyTable -w 500 --precision 3 -t 20
    hr
    # write to 100 regions...
    run ./check_hbase_write_spray.py -T HexStringSplitTable -w 500 --precision 3 -t 20
    hr
    run_fail 2 ./check_hbase_write_spray.py -T DisabledTable -t 5
    hr
    run_fail 2 ./check_hbase_write_spray.py -T NonExistentTable -t 5
# ============================================================================ #
    hr
    # have to use --host and --port here as this is a generic program with specific environment variables like we're setting and don't want to set $HOST and $PORT
    run $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P "$HBASE_REGIONSERVER_PORT" --bean Hadoop:service=HBase,name=RegionServer,sub=Server -m compactionQueueLength
    hr
    run $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P "$HBASE_REGIONSERVER_PORT" --bean Hadoop:service=HBase,name=RegionServer,sub=Server --all-metrics -t 30 | sed 's/|.*$//' # too long exceeds Travis CI max log length due to the 100 region HexStringSplitTable multiplying out the available metrics
    hr
    run $perl -T ./check_hadoop_jmx.pl -H $HBASE_HOST -P "$HBASE_REGIONSERVER_PORT" --all-metrics -t 20
    #hr
    # XXX: both cause 500 internal server error
    #$perl -T ./check_hadoop_metrics.pl -H $HBASE_HOST -P "$HBASE_MASTER_PORT" --all-metrics
    #$perl -T ./check_hadoop_metrics.pl -H $HBASE_HOST -P "$HBASE_MASTER_PORT" -m compactionQueueLength
    #hr
    #$perl -T ./check_hadoop_metrics.pl -H $HBASE_HOST -P "$HBASE_REGIONSERVER_PORT" --all-metrics
    #$perl -T ./check_hadoop_metrics.pl -H $HBASE_HOST -P "$HBASE_REGIONSERVER_PORT" -m compactionQueueLength
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
    run ./check_hbase_table_region_balance.py -T t1
    hr
    run ./check_hbase_table_region_balance.py -T EmptyTable
    hr
    run ./check_hbase_table_region_balance.py -T DisabledTable
    hr
    # all tables
    run ./check_hbase_table_region_balance.py
    hr
    run_fail 3 ./check_hbase_table_region_balance.py --list-tables
    hr
    docker_exec check_hbase_table_rowcount.pl -T t1 --hbase-bin /hbase/bin/hbase -w 3:3 -c 3:3 -t 60
    hr
    if is_zookeeper_built; then
        # This also checks that check_hbase_write.py deleted correctly
        run $perl -T ./check_hbase_table_rowcount.pl -T EmptyTable --hbase-bin /hbase/bin/hbase -w 0:0 -c 0:0 -t 30
        hr
        run $perl -T ./check_zookeeper_znode.pl -H localhost -z /hbase -v -n --child-znodes
        hr
        run $perl -T ./check_zookeeper_child_znodes.pl -H localhost -z /hbase/rs -v -w 1:1 -c 1:1
        # XXX: not present all the time
        #$perl -T ./check_hbase_unassigned_regions_znode.pl
    else
        # Use Docker hbase-dev, zookeeper will have been built in there
        echo "ZooKeeper not built - running ZooKeeper checks in docker container:"
        # This also checks that check_hbase_write.py deleted correctly
        docker_exec check_hbase_table_rowcount.pl -T EmptyTable --hbase-bin /hbase/bin/hbase -w 0:0 -c 0:0 -t 30
        hr
        docker_exec check_zookeeper_znode.pl -H localhost -z /hbase -v -n --child-znodes
        hr
        docker_exec check_zookeeper_child_znodes.pl -H localhost -z /hbase/rs -v -w 1:1 -c 1:1
        # XXX: not present all the time
        #docker_exec check_hbase_unassigned_regions_znode.pl -H localhost
    fi
    hr

# ============================================================================ #
    if [ -n "${KEEPDOCKER:-}" ]; then
        echo
        echo "Completed $run_count HBase tests"
        return
    fi
    echo "Forced Failure Scenarios:"
    echo "sending kill signal to RegionServer"
    docker exec -ti "$DOCKER_CONTAINER" pkill -f RegionServer
    # This doesn't work because the port still responds as open, even when the mapped port is down
    # must be a result of docker networking
    #when_ports_down 20  "$HBASE_HOST" "$HBASE_REGIONSERVER_PORT"
    i=20
    max_iterations=20
    while docker exec "$DOCKER_CONTAINER" ps -ef | grep -q RegionServer; do
        let i+=1
        if [ $max_iterations -gt $max_iterations ]; then
            echo "RegionServer process did not go down after $max_iterations secs!"
            exit 1
        fi
        echo "waiting for RegionServer process to go down"
        sleep 1
    done
    hr
    run_fail 2 $perl -T ./check_hbase_regionservers.pl
    hr
    # should still exit critical as there are no remaining regionservers live
    run_fail 2 $perl -T ./check_hbase_regionservers.pl -w 2 -c 2
    hr
# ============================================================================ #
    run_fail 2 $perl -T ./check_hbase_regionservers_jsp.pl
    hr
    # should still exit critical as there are no remaining regionservers live
    run_fail 2 $perl -T ./check_hbase_regionservers_jsp.pl -w 2 -c 2
    hr
# ============================================================================ #
    echo "Thrift API checks will hang so these python plugins will self timeout with UNKNOWN when the sole RegionServer is down"
    run_fail 3 ./check_hbase_table.py -T t1 -t 5
    hr
    run_fail 3 ./check_hbase_table_enabled.py -T t1 -t 5
    hr
    run_fail 3 ./check_hbase_table_regions.py -T DisabledTable -t 5
    hr
    run_fail 3 ./check_hbase_cell.py -T t1 -R r1 -C cf1:q1 -t 5
    hr
    echo "sending kill signal to ThriftServer"
    docker-compose exec "$DOCKER_SERVICE" pkill -f ThriftServer
    # leaving a race condition here intentionally as depending on timing it may trigger
    # either connection refused or connection reset but the code has been upgraded to handle
    # both as CRITICAL rather than falling through to the UNKNOWN status handler in the pylib framework
    echo "waiting 2 secs for ThriftServer to go down"
    sleep 2
    echo "Thrift API checks should now fail with exit code 2:"
    run_fail 2 ./check_hbase_table.py -T t1
    hr
    run_fail 2 ./check_hbase_table_enabled.py -T t1
    hr
    run_fail 2 ./check_hbase_table_regions.py -T DisabledTable
    hr
    run_fail 2 ./check_hbase_cell.py -T t1 -R r1 -C cf1:q1
    hr
    echo "Completed $run_count HBase tests"
    hr
    # will return further above and not use this
    #[ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
    echo
}

run_test_versions HBase
