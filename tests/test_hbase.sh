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

# shellcheck disable=SC1090
. "$srcdir2/utils.sh"

srcdir="$srcdir2"

section "H B a s e"

if [ "${HBASE_IMAGE:-}" = hbase ]; then
    echo "checking harisekhon/hbase image, skipping docker exec checks..."
    export HBASE_IMAGE
    export DOCKER_SKIP_EXEC=1  # don't run local tests which requires harisekhon/hbase-dev containing pre-built dependencies
fi

export HBASE_VERSIONS="${*:-${HBASE_VERSIONS:-0.98 1.0 1.1 1.2 1.3 1.4 2.0 2.1 latest}}"
if ! is_CI; then
    export HBASE_VERSIONS="0.90 0.92 0.94 0.95 0.96 $HBASE_VERSIONS"
fi

HBASE_HOST="${DOCKER_HOST:-${HBASE_HOST:-${HOST:-localhost}}}"
HBASE_HOST="${HBASE_HOST##*/}"
HBASE_HOST="${HBASE_HOST%%:*}"
export HBASE_HOST
export HBASE_MASTER_PORT_DEFAULT=16010
export HAPROXY_MASTER_PORT_DEFAULT=16010
export HBASE_REGIONSERVER_TCP_PORT_DEFAULT=16020
export HBASE_REGIONSERVER_PORT_DEFAULT=16030
export HBASE_STARGATE_PORT_DEFAULT=8080
export HAPROXY_STARGATE_PORT_DEFAULT=8080
export HBASE_STARGATE_UI_PORT_DEFAULT=8085
export HAPROXY_STARGATE_UI_PORT_DEFAULT=8085
export HBASE_THRIFT_PORT_DEFAULT=9090
export HAPROXY_THRIFT_PORT_DEFAULT=9090
export HBASE_THRIFT_UI_PORT_DEFAULT=9095
export HAPROXY_THRIFT_UI_PORT_DEFAULT=9095
export ZOOKEEPER_PORT_DEFAULT=2181

# in case it's set in ~/.bashrc for other tools, don't docker exec to this user as it probably won't exist in the container
unset DOCKER_USER

check_docker_available

trap_debug_env hbase

startupwait 60

export DOCKER_MOUNT_DIR="/pl"

export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-docker}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME//-}"

dump_hbck_log(){
    local hbck_log="$1"
    if ! is_latest_version; then
        if ! test -s "$hbck_log"; then
            echo "copying NEW $hbck_log from HBase $version container:"
            docker cp "$DOCKER_CONTAINER":/tmp/hbase-hbck.log "$hbck_log"
            echo "adding new $hbck_log to git:"
            # .log paths are excluded, must -f or this will fail
            git add -f "$hbck_log"
            hr
        fi
    fi
}

test_hbase(){
    local version="$1"
    section2 "Setting up HBase $version test container"
    # we kill RegionServer and Thrift server near the end to test failure scenarios so do not re-use these containers
    docker_compose_pull
    if [ -z "${KEEPDOCKER:-}" ]; then
        docker-compose down || :
    fi
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    # HBase 0.9x / 2.x uses RegionServer port 16030, 1.x series changed to 16301 then changed back in 2.x
    #if [[ "${version:0:2}" =~ ^1\. ]]; then
    #    local export HBASE_REGIONSERVER_PORT_DEFAULT=16301
    if [[ "${version:0:3}" =~ ^0\.9 ]]; then
        local export HBASE_REGIONSERVER_PORT_DEFAULT=60301
    fi
    # HBase <= 0.99 uses older port numbers
    if [[ "${version:0:4}" =~ ^0\.9[0-8]$ ]]; then
        local export HBASE_MASTER_PORT_DEFAULT=60010
        local export HAPROXY_MASTER_PORT_DEFAULT=60010
    fi
    echo "getting HBase dynamic port mappings:"
    docker_compose_port "HBase Master"
    docker_compose_port "HBase RegionServer"
    docker_compose_port "HBase RegionServer TCP"
    docker_compose_port "HBase Stargate"
    docker_compose_port "HBase Stargate UI"
    docker_compose_port "HBase Thrift"
    docker_compose_port "HBase Thrift UI"
    DOCKER_SERVICE=hbase-haproxy docker_compose_port HAPROXY_MASTER_PORT "HAProxy HBase Master"
    DOCKER_SERVICE=hbase-haproxy docker_compose_port HAPROXY_STARGATE_PORT "HAProxy Stargate"
    DOCKER_SERVICE=hbase-haproxy docker_compose_port HAPROXY_STARGATE_UI_PORT "HAProxy Stargate UI"
    DOCKER_SERVICE=hbase-haproxy docker_compose_port HAPROXY_THRIFT_PORT "HAProxy Thrift"
    DOCKER_SERVICE=hbase-haproxy docker_compose_port HAPROXY_THRIFT_UI_PORT "HAProxy Thrift UI"
    #docker_compose_port ZOOKEEPER_PORT "HBase ZooKeeper"
    export HBASE_PORTS="$HBASE_MASTER_PORT $HBASE_REGIONSERVER_PORT $HBASE_REGIONSERVER_TCP_PORT $HBASE_STARGATE_PORT $HBASE_THRIFT_PORT"
    hr
    # want splitting
    # shellcheck disable=SC2086
    when_ports_available "$HBASE_HOST" $HBASE_PORTS
    hr
    if [ "$version" = "0.90" ]; then
        when_url_content "http://$HBASE_HOST:$HBASE_MASTER_PORT/master.jsp" HBase
        hr
        echo "checking HAProxy HBase Master:"
        when_url_content "http://$HBASE_HOST:$HAPROXY_MASTER_PORT/master.jsp" HBase
        hr
        when_url_content "http://$HBASE_HOST:$HBASE_REGIONSERVER_PORT/regionserver.jsp" HBase
    elif [ "${version:0:3}" = "0.9" ]; then
        when_url_content "http://$HBASE_HOST:$HBASE_MASTER_PORT/master-status" HBase
        hr
        echo "checking HAProxy HBase Master:"
        when_url_content "http://$HBASE_HOST:$HAPROXY_MASTER_PORT/master-status" HBase
        hr
        when_url_content "http://$HBASE_HOST:$HBASE_REGIONSERVER_PORT/rs-status" HBase
    else
        when_url_content "http://$HBASE_HOST:$HBASE_MASTER_PORT/master-status" HMaster
        hr
        echo "checking HAProxy HBase Master:"
        when_url_content "http://$HBASE_HOST:$HAPROXY_MASTER_PORT/master-status" HMaster
        hr
        when_url_content "http://$HBASE_HOST:$HBASE_REGIONSERVER_PORT/rs-status" "HBase Region Server"
    fi
    hr
    if [ "$version" = "0.92" ]; then
        # HBase 0.92 gets following errors when trying to create tables:
        # org.apache.hadoop.hbase.PleaseHoldException: org.apache.hadoop.hbase.PleaseHoldException: Master is initializing
        when_url_content "http://$HBASE_HOST:$HBASE_MASTER_PORT/master-status" "Initialization successful"
        hr
    fi
    echo "checking HBase Stargate:"
    when_url_content "http://$HBASE_HOST:$HAPROXY_STARGATE_UI_PORT/rest.jsp" "HBase.+REST"
    hr
    echo "checking HBase Thrift:"
    when_url_content "http://$HBASE_HOST:$HAPROXY_THRIFT_UI_PORT/thrift.jsp" "HBase.+Thrift"
    hr
    # tr occasionally errors out due to weird input chars, base64 for safety, but still remove chars like '+' which will ruin --expected regex
    local uniq_val
    uniq_val="$(< /dev/urandom base64 | tr -dc 'a-zA-Z0-9' 2>/dev/null | head -c32 || :)"
    # gets ValueError: file descriptor cannot be a negative integer (-1), -T should be the workaround but hangs
    #docker-compose exec -T "$DOCKER_SERVICE" /bin/bash <<-EOF
    [ -n "${NOSETUP:-}" ] ||
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
    set -euo pipefail
    echo "setting up test tables"
    if [ -n "${DEBUG:-}" ]; then
        set -x
    fi
    export JAVA_HOME=/usr
    /hbase/bin/hbase shell <<-EOF2
        create 't1', 'cf1'
        create 'EmptyTable', 'cf2', 'cf3'
        create 'DisabledTable', 'cf4'
        disable 'DisabledTable'
        put 't1', 'r1', 'cf1:q1', '$uniq_val'
        put 't1', 'r2', 'cf1:q1', 'test'
        put 't1', 'r3', 'cf1:q1', '5'
        list
        balance_switch false
EOF2
    # don't actually use this table in tests, only in pytools repo
    #hbase org.apache.hadoop.hbase.util.RegionSplitter UniformSplitTable UniformSplit -c 100 -f cf1
    if [ "$version" = 0.90 -o "$version" = 0.92 ]; then
        hbase org.apache.hadoop.hbase.util.RegionSplitter HexStringSplitTable -c 100 -f cf1
    else
        hbase org.apache.hadoop.hbase.util.RegionSplitter HexStringSplitTable HexStringSplit -c 100 -f cf1
    fi
    echo "creating hbck.log"
    hbase hbck &> /tmp/hbase-hbck.log
    echo "test setup finished"
    exit 0
EOF
    hr
    data_dir="tests/data"
    local hbck_log="$data_dir/hbase-hbck-$version.log"
    #dump_hbck_log "$hbck_log"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    echo "starting tests for version $version"
    if is_latest_version; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version
        version="$(dockerhub_latest_version hbase-dev)"
        echo "expecting version '$version'"
    fi
    hr
    # Not available on HBase 0.90
    if [ "$version" != "0.90" ]; then
        run ./check_hbase_master_version.py -e "$version"

        run_fail 2 ./check_hbase_master_version.py -e "fail-version"

        run_fail 2 ./check_hbase_regionserver_version.py -e "fail-version"

        run ./check_hbase_regionserver_version.py -e "$version"
    fi

    run_conn_refused ./check_hbase_master_version.py -e "$version"

    run_conn_refused ./check_hbase_regionserver_version.py -e "$version"

    run ./check_hbase_hbck.py -f tests/data/hbck.log -a 0

    run_fail 1 ./check_hbase_hbck.py -f tests/data/hbck.log -a 3

    docker_exec check_hbase_hbck.py -f /tmp/hbase-hbck.log -a 60

    ERRCODE=1 docker_exec check_hbase_hbck.py -f /tmp/hbase-hbck.log -a 1

    run_fail 2 ./check_hbase_hbck.py -f tests/data/hbck-inconsistencies.log -a 0

    run_fail 2 ./check_hbase_hbck.py -f tests/data/hbck-inconsistencies.log -a 3

    run_fail 3 ./check_hbase_hbck.py -f nonexistent_file

    run ./check_hbase_master_java_gc.py -w 10 -c 10
    run ./check_hbase_regionserver_java_gc.py -w 10 -c 10

    run_fail 2 ./check_hbase_master_java_gc.py -c 0
    run_fail 2 ./check_hbase_regionserver_java_gc.py -c 0

    run_conn_refused ./check_hbase_master_java_gc.py
    run_conn_refused ./check_hbase_regionserver_java_gc.py

# ============================================================================ #

    # HBase versions 1.0 and <= 0.96 don't seem to report when balancer is disabled in UI
    if ! [[ "${version:0:4}" =~ ^0\.9[0-6]|^1.0 ]]; then
        run_fail 1 ./check_hbase_balancer_enabled.py

        run_fail 1 ./check_hbase_balancer_enabled2.py
    fi

    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
    export JAVA_HOME=/usr
    /hbase/bin/hbase shell <<-EOF2
        balance_switch true
EOF2
EOF

    retry 10 ./check_hbase_balancer_enabled2.py

    run ./check_hbase_balancer_enabled.py

    run ./check_hbase_balancer_enabled2.py

    run_conn_refused ./check_hbase_balancer_enabled.py

    run_conn_refused ./check_hbase_balancer_enabled2.py

# ============================================================================ #

    run ./check_hbase_table_enabled.py -T t1

    run_conn_refused ./check_hbase_table_enabled.py -T t1

    run ./check_hbase_table_enabled.py -T EmptyTable

    # broken on <= 0.94 it returns enabled for DisabledTable
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run_fail "0 2" ./check_hbase_table_enabled.py -T DisabledTable
    else
        run_fail 2 ./check_hbase_table_enabled.py -T DisabledTable
    fi

    # broken on 0.92, 0.94, 0.96 it incorrectly returns enabled for nonexistent_table
    if [[ "$version" =~ ^0\.9[2-6]$ ]]; then
        run ./check_hbase_table_enabled.py -T nonexistent_table
    else
        run_fail 2 ./check_hbase_table_enabled.py -T nonexistent_table
    fi

# ============================================================================ #

    # HBase <= 0.94 gets IOError
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run_fail "0 2" ./check_hbase_table.py -T t1
    else
        run ./check_hbase_table.py -T t1
    fi

    run_conn_refused ./check_hbase_table.py -T t1

    # HBase <= 0.94 gets IOError
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run_fail "0 2" ./check_hbase_table.py -T EmptyTable
    else
        run ./check_hbase_table.py -T EmptyTable
    fi

    run_fail 2 ./check_hbase_table.py -T DisabledTable

    run_fail 2 ./check_hbase_table.py -T nonexistent_table

# ============================================================================ #

    # HBase 0.90 + 0.92 gets unassigned region
    if [[ "$version" =~ ^0\.9[02]$ ]]; then
        run_fail 1 ./check_hbase_table_regions.py -T t1
    # HBase 0.94 fails to get regions
    elif [ "$version" = "0.94" ]; then
        run_fail "0 2" ./check_hbase_table_regions.py -T t1
    else
        run ./check_hbase_table_regions.py -T t1
    fi

    run_conn_refused ./check_hbase_table_regions.py -T t1

    # HBase 0.90 + 0.92 gets unassigned region
    if [[ "$version" =~ ^0\.9[02]$ ]]; then
        run_fail 1 ./check_hbase_table_regions.py -T EmptyTable
    # HBase 0.94 fails to get regions
    elif [ "$version" = "0.94" ]; then
        run_fail "0 2" ./check_hbase_table_regions.py -T EmptyTable
    else
        run ./check_hbase_table_regions.py -T EmptyTable
    fi

    # HBase 0.90 + 0.92 gets unassigned region
    if [[ "$version" =~ ^0\.9[02]$ ]]; then
        run_fail 1 ./check_hbase_table_regions.py -T DisabledTable
    # HBase 0.94 fails to get regions
    elif [ "$version" = "0.94" ]; then
        run_fail "0 2" ./check_hbase_table_regions.py -T DisabledTable
    else
        # even though DisabledTable table is disabled, it still has assigned regions
        run ./check_hbase_table_regions.py -T DisabledTable
    fi

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

    # 0.90 fails to parse
    if [ "$version" = "0.90" ]; then
        run_fail 3 ./check_hbase_table_compaction_in_progress.py -T t1
    # HBase <= 0.94 does not find the table
    elif [[ "$version" =~ ^0\.9[2-4]$ ]]; then
        run_fail "0 2" ./check_hbase_table_compaction_in_progress.py -T t1
    else
        run ./check_hbase_table_compaction_in_progress.py -T t1
    fi

    run_conn_refused ./check_hbase_table_compaction_in_progress.py -T t1

    # 0.90 fails to parse
    if [ "$version" = "0.90" ]; then
        run_fail 3 ./check_hbase_table_compaction_in_progress.py -T EmptyTable
    # HBase <= 0.94 does not find the table
    elif [[ "$version" =~ ^0\.9[2-4]$ ]]; then
        run_fail "0 2" ./check_hbase_table_compaction_in_progress.py -T EmptyTable
    else
        run ./check_hbase_table_compaction_in_progress.py -T EmptyTable
    fi

    # HBase 0.90 + 0.95 fails to parse the table page
    if [[ "$version" =~ ^0\.9[05]$ ]]; then
        run_fail 3 ./check_hbase_table_compaction_in_progress.py -T DisabledTable
    # HBase <= 0.94 fails to parse as this info isn't available in the table page
    elif [[ "$version" =~ ^0\.9[2-4]$ ]]; then
        run_fail 3 ./check_hbase_table_compaction_in_progress.py -T DisabledTable
    else
        run ./check_hbase_table_compaction_in_progress.py -T DisabledTable
    fi

    run_fail 2 ./check_hbase_table_compaction_in_progress.py -T nonexistent_table

# ============================================================================ #

    # HBase 0.90 gets 404
    if [ "$version" = "0.90" ]; then
        run_404 ./check_hbase_region_balance.py
    # HBase <= 0.94 fails to parse region info
    elif [[ "$version" =~ ^0\.9[2-4]$ ]]; then
        run_fail 3 ./check_hbase_region_balance.py
    else
        run ./check_hbase_region_balance.py
    fi

    run_conn_refused ./check_hbase_region_balance.py

    # HBase 0.90 gets 404
    if [ "$version" = "0.90" ]; then
        run_404 ./check_hbase_regions_stuck_in_transition.py
    # HBase <= 0.94 fails to parse region info
    elif [[ "$version" =~ ^0\.9[2-4]$ ]]; then
        run_fail 3 ./check_hbase_regions_stuck_in_transition.py
    else
        run ./check_hbase_regions_stuck_in_transition.py
    fi

    # HBase 0.90 gets 404
    if [ "$version" = "0.90" ]; then
        run_404 ./check_hbase_num_regions_in_transition.py
    # HBase <= 0.94 fails to parse region info
    elif [[ "$version" =~ ^0\.9[2-4]$ ]]; then
        run_fail 3 ./check_hbase_num_regions_in_transition.py
    else
        run ./check_hbase_num_regions_in_transition.py
    fi

    # HBase 0.90 gets 404
    if [ "$version" = "0.90" ]; then
        run_404 ./check_hbase_regionserver_compaction_in_progress.py
    # HBase <= 0.94 fails to parse region info
    elif [[ "$version" =~ ^0\.9[2-4]$ ]]; then
        run_fail 3 ./check_hbase_regionserver_compaction_in_progress.py
    else
        run ./check_hbase_regionserver_compaction_in_progress.py
    fi

    echo "ensuring Stargate Server is properly online before running this test:"
    when_url_content "http://$HBASE_HOST:$HBASE_STARGATE_PORT/" HexStringSplitTable
    hr

    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    run "$perl" -T ./check_hbase_regionservers.pl

    run_conn_refused "$perl" -T ./check_hbase_regionservers.pl

    if [ "$version" = "0.90" ]; then
        run_404 "$perl" -T ./check_hbase_regionservers_jsp.pl
    else
        run "$perl" -T ./check_hbase_regionservers_jsp.pl
    fi

    run_conn_refused "$perl" -T ./check_hbase_regionservers_jsp.pl

    run ./check_hbase_regionservers_requests_balance.py

    run_conn_refused ./check_hbase_regionservers_requests_balance.py

# ============================================================================ #

    for x in "$perl -T ./check_hbase_cell.pl" ./check_hbase_cell.py "$perl -T ./check_hbase_cell_stargate.pl"; do
        # HBase <= 0.94 fails to retrieve cell
        if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
            run_fail "0 2" eval "$x" -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
            # TODO: fix up the rest of these checks to work
            continue
        else
            run eval "$x" -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
        fi

        run_conn_refused eval "$x" -T t1 -R r1 -C cf1:q1 -e "$uniq_val"

        # HBase <= 0.94 fails to retrieve cell
        if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
            run_fail "0 2" eval "$x" -T t1 -R r2 -C cf1:q1 --expected test --precision 3

            run_fail "0 2" eval "$x" -T t1 -R r3 -C cf1:q1 -e 5 -w 5 -c 10 -g -u ms
        else
            run eval "$x" -T t1 -R r2 -C cf1:q1 --expected test --precision 3

            run eval "$x" -T t1 -R r3 -C cf1:q1 -e 5 -w 5 -c 10 -g -u ms
        fi

        run_fail 1 eval "$x" -T t1 -R r3 -C cf1:q1 -e 5 -w 4 -c 10

        run_fail 2 eval "$x" -T t1 -R r3 -C cf1:q1 -e 5 -w 4 -c 4

        run_fail 2 eval "$x" -T t1 -R nonExistentRow -C cf1:q1

        run_fail 2 eval "$x" -T t1 -R r1 -C nonExistentCF:q1

        run_fail 2 eval "$x" -T t1 -R r1 -C cf1:nonExistentQF

        run_fail 2 eval "$x" -T NonExistentTable -R r1 -C cf1:q1

        run_fail 2 eval "$x" -T DisabledTable -R r1 -C cf1:q1

        run_fail 2 eval "$x" -T EmptyTable -R r1 -C cf1:q1
    done

    # ./check_hbase_cell_thrift.pl is only a symlink to check_hbase_cell.pl so just check it's still there and working
    # HBase 0.94 fails to retrieve cell
    if [ "$version" = "0.94" ]; then
        run_fail "0 2" "$perl" -T ./check_hbase_cell_thrift.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
    else
        run "$perl" -T ./check_hbase_cell_thrift.pl -T t1 -R r1 -C cf1:q1 -e "$uniq_val"
    fi

# ============================================================================ #

    # HBase <= 0.94 gets CRITICAL: IOError(message='t1')
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run_fail "0 2" ./check_hbase_write.py -T t1 -w 500 --precision 3
    else
        run ./check_hbase_write.py -T t1 -w 500 --precision 3
    fi

    run_conn_refused ./check_hbase_write.py -T t1 -w 100 --precision 3

    # this will also be checked later by check_hbase_rowcount that it returns to zero rows, ie. delete succeeded
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run_fail "0 2" ./check_hbase_write.py -T EmptyTable -w 100 --precision 3
    else
        run ./check_hbase_write.py -T EmptyTable -w 100 --precision 3
    fi

    run_fail 2 ./check_hbase_write.py -T DisabledTable -t 2

    run_fail 2 ./check_hbase_write.py -T NonExistentTable

# ============================================================================ #

    # setting hbase write --warning millisecs high as I want these tests to pass even on a loaded workstation or CI server

    # HBase <= 0.94 gets CRITICAL: IOError(message='t1')
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run_fail "0 2" ./check_hbase_write_spray.py -T t1 -w 700 --precision 3 -t 60
    else
        run ./check_hbase_write_spray.py -T t1 -w 700 --precision 3 -t 60
    fi

    run_conn_refused ./check_hbase_write_spray.py -T t1 -w 500 --precision 3 -t 60

    # HBase <= 0.94 gets CRITICAL: IOError(message='t1')
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run_fail "0 2" ./check_hbase_write_spray.py -T t1 -w 500 --precision 3 -t 60
        run_fail "0 2" ./check_hbase_write_spray.py -T EmptyTable -w 500 --precision 3 -t 60
    else
        # this will also be checked later by check_hbase_rowcount that it returns to zero rows, ie. delete succeeded
        run ./check_hbase_write_spray.py -T EmptyTable -w 700 --precision 3 -t 60

    fi

    # not sure why this succeeds on HBase 0.94 but check_hbase_write.py does not
    # write to 100 regions...
    run ./check_hbase_write_spray.py -T HexStringSplitTable -w 700 --precision 3 -t 60

    run_fail 2 ./check_hbase_write_spray.py -T DisabledTable -t 5

    run_fail 2 ./check_hbase_write_spray.py -T NonExistentTable -t 5

# ============================================================================ #

    # HBase <= 0.94 doesn't have this mbean
    if ! [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        # have to use --host and --port here as this is a generic program with specific environment variables like we're setting and don't want to set $HOST and $PORT
        run "$perl" -T ./check_hadoop_jmx.pl -H "$HBASE_HOST" -P "$HBASE_REGIONSERVER_PORT" --bean Hadoop:service=HBase,name=RegionServer,sub=Server -m compactionQueueLength

        run "$perl" -T ./check_hadoop_jmx.pl -H "$HBASE_HOST" -P "$HBASE_REGIONSERVER_PORT" --bean Hadoop:service=HBase,name=RegionServer,sub=Server --all-metrics -t 20 | sed 's/|.*$//'
    fi

    # too long exceeds Travis CI max log length due to the 100 region HexStringSplitTable multiplying out the available metrics
    if [ "$version" = "0.90" ]; then
        run_404 "$perl" -T ./check_hadoop_jmx.pl -H "$HBASE_HOST" -P "$HBASE_REGIONSERVER_PORT" --all-metrics -t 20 | sed 's/|.*$//'
    else
        run "$perl" -T ./check_hadoop_jmx.pl -H "$HBASE_HOST" -P "$HBASE_REGIONSERVER_PORT" --all-metrics -t 20 | sed 's/|.*$//'
    fi

    run_conn_refused "$perl" -T ./check_hadoop_jmx.pl --bean Hadoop:service=HBase,name=RegionServer,sub=Server -m compactionQueueLength

    ######################
    # use newer Python version "check_hbase_table.py" for Hbase 0.95+ instead of older plugins in this section
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run "$perl" -T ./check_hbase_tables.pl
    else
        run_fail 2 "$perl" -T ./check_hbase_tables.pl
    fi

    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run "$perl" -T ./check_hbase_tables_thrift.pl

        run "$perl" -T ./check_hbase_tables_stargate.pl

        run "$perl" -T ./check_hbase_tables_jsp.pl
    else
        run_fail 2 "$perl" -T ./check_hbase_tables_thrift.pl

        run_fail 2 "$perl" -T ./check_hbase_tables_stargate.pl

        run_fail 2 "$perl" -T ./check_hbase_tables_jsp.pl
    fi

    ######################

    # HBase <= 0.94 fails to find table
    if [[ "$version" =~ ^0\.9[0-4]$ ]]; then
        run_fail "0 2" ./check_hbase_table_region_balance.py -T t1

        run_fail "0 2" ./check_hbase_table_region_balance.py -T EmptyTable

        run_fail "0 2" ./check_hbase_table_region_balance.py -T DisabledTable
    else
        run ./check_hbase_table_region_balance.py -T t1

        run ./check_hbase_table_region_balance.py -T EmptyTable

        run ./check_hbase_table_region_balance.py -T DisabledTable

    fi

    # all tables
    run ./check_hbase_table_region_balance.py

    run_conn_refused ./check_hbase_table_region_balance.py -T t1

    run_conn_refused ./check_hbase_table_region_balance.py

    run_fail 3 ./check_hbase_table_region_balance.py --list-tables

    docker_exec check_hbase_table_rowcount.pl -T t1 --hbase-bin /hbase/bin/hbase -w 3:3 -c 3:3 -t 60

    if is_zookeeper_built; then
        # This also checks that check_hbase_write.py deleted correctly
        run "$perl" -T ./check_hbase_table_rowcount.pl -T EmptyTable --hbase-bin /hbase/bin/hbase -w 0:0 -c 0:0 -t 30

        run "$perl" -T ./check_zookeeper_znode.pl -H "$HBASE_HOST" -z /hbase -v -n --child-znodes

        run_conn_refused "$perl" -T ./check_zookeeper_znode.pl -z /hbase -v -n --child-znodes

        run "$perl" -T ./check_zookeeper_child_znodes.pl -H "$HBASE_HOST" -z /hbase/rs -v -w 1:1 -c 1:1

        run_conn_refused "$perl" -T ./check_zookeeper_child_znodes.pl -z /hbase/rs -v -w 1:1 -c 1:1

        # XXX: not present all the time
        #$perl -T ./check_hbase_unassigned_regions_znode.pl
    else
        # Use Docker hbase-dev, zookeeper will have been built in there
        echo "ZooKeeper not built - running ZooKeeper checks in docker container:"
        # This also checks that check_hbase_write.py deleted correctly
        docker_exec check_hbase_table_rowcount.pl -T EmptyTable --hbase-bin /hbase/bin/hbase -w 0:0 -c 0:0 -t 30

        docker_exec check_zookeeper_znode.pl -H localhost -z /hbase -v -n --child-znodes

        ERRCODE=2 docker_exec check_zookeeper_znode.pl -H localhost -z /hbase -v -n --child-znodes -P "$wrong_port"

        docker_exec check_zookeeper_child_znodes.pl -H localhost -z /hbase/rs -v -w 1:1 -c 1:1

        ERRCODE=2 docker_exec check_zookeeper_child_znodes.pl -H localhost -z /hbase/rs -v -w 1:1 -c 1:1 -P "$wrong_port"

        # XXX: not present all the time
        #docker_exec check_hbase_unassigned_regions_znode.pl -H localhost
    fi

    #####################
    # give these more time as error reminds these metrics aren't available soon after start
    # TODO: perhaps this only works on some versions now??? Test and re-enable for those versions
    # XXX: this used to work, now cannot find metrics
    run_fail "0 2 3" "$perl" -T ./check_hbase_metrics.pl -H "$HBASE_HOST" -P "$HBASE_MASTER_PORT" --all-metrics
    run_fail "0 2 3" "$perl" -T ./check_hbase_metrics.pl -H "$HBASE_HOST" -P "$HBASE_MASTER_PORT" -m compactionQueueLength

    run_fail "0 2 3" "$perl" -T ./check_hbase_metrics.pl -H "$HBASE_HOST" -P "$HBASE_REGIONSERVER_PORT" --all-metrics
    run_fail "0 2 3" "$perl" -T ./check_hbase_metrics.pl -H "$HBASE_HOST" -P "$HBASE_REGIONSERVER_PORT" -m compactionQueueLength

# ============================================================================ #

    if [ -n "${KEEPDOCKER:-}" ]; then
        echo
        # defined and tracked in bash-tools/lib/utils.sh
        # shellcheck disable=SC2154
        echo "Completed $run_count HBase tests"
        return
    fi
    echo "Forced Failure Scenarios:"
    echo "sending kill signal to RegionServer"
    # doesn't have procps in build yet, otherwise -i and collapse next 2 lines
    docker exec -ti "$DOCKER_CONTAINER" pkill -f RegionServer || :
    # for HBase <= 0.94
    docker exec -ti "$DOCKER_CONTAINER" pkill -f regionserver || :
    # This doesn't work because the port still responds as open, even when the mapped port is down
    # must be a result of docker networking
    #when_ports_down 20  "$HBASE_HOST" "$HBASE_REGIONSERVER_PORT"
    SECONDS=0
    max_kill_time=20
    while docker exec "$DOCKER_CONTAINER" ps -ef | grep -q RegionServer; do
        if [ $SECONDS -gt $max_kill_time ]; then
            echo "RegionServer process did not go down after $max_kill_time secs!"
            exit 1
        fi
        echo "waiting for RegionServer process to go down"
        sleep 1
    done
    hr
    echo "waiting for Stargate info to get updated for downed RegionServer:"
    retry 20 ! "$perl" -T ./check_hbase_regionservers.pl
    hr
    # default critical = 1 but will raise critical if there are no more live regionservers
    run_fail 2 "$perl" -T ./check_hbase_regionservers.pl

    # should still exit critical as there are no remaining regionservers live
    run_fail 2 "$perl" -T ./check_hbase_regionservers.pl -w 2 -c 2

# ============================================================================ #

    run_fail 2 "$perl" -T ./check_hbase_regionservers_jsp.pl

    # should still exit critical as there are no remaining regionservers live
    run_fail 2 "$perl" -T ./check_hbase_regionservers_jsp.pl -w 2 -c 2

# ============================================================================ #

    echo "Thrift API checks will hang when sole RegionServer is down - testing python plugins will self timeout with UNKNOWN in this scenario:"
    # looks like this is cached and succeeds in 0.96 / 0.98
    run_fail "0 3" ./check_hbase_table.py -T t1 -t 5

    run_fail "0 3" ./check_hbase_table_enabled.py -T t1 -t 5

    run_timeout ./check_hbase_table_regions.py -T DisabledTable -t 5

    run_timeout ./check_hbase_cell.py -T t1 -R r1 -C cf1:q1 -t 5

    echo "sending kill signal to ThriftServer"
    docker-compose exec "$DOCKER_SERVICE" pkill -f ThriftServer || :
    # HBase <= 0.94
    docker-compose exec "$DOCKER_SERVICE" pkill -f -- hbase.log.file=hbase--thrift- || :
    # intentionally leaving a race condition here as depending on timing it may trigger
    # either connection refused or connection reset but the code has been upgraded to handle both
    # as CRITICAL rather than falling through to the UNKNOWN status handler in the pylib framework
    # so this actually tests the robustness of the code to return CRITICAL in either case
    echo "Sleeping for 2 secs to before continuing with Thrift Server failure checks"
    sleep 2
#    SECONDS=0
#    max_kill_time=20
#    while docker exec "$DOCKER_CONTAINER" ps -ef | grep -q thrift; do
#        if [ $SECONDS -gt $max_kill_time ]; then
#            echo "ThriftServer process did not go down after $max_kill_time secs!"
#            exit 1
#        fi
#        echo "waiting for ThriftServer process to go down"
#        sleep 1
#    done
    echo "Thrift API checks should now fail with exit code 2:"
    run_fail 2 ./check_hbase_table.py -T t1

    run_fail 2 ./check_hbase_table_enabled.py -T t1

    run_fail 2 ./check_hbase_table_regions.py -T DisabledTable

    run_fail 2 ./check_hbase_cell.py -T t1 -R r1 -C cf1:q1

    # Doesn't give any failure in hbck log when RegionServer is down
#    local hbck_log="$data_dir/hdfs-hbck-fail-$version.log"
#    if ! is_CI; then
#        if ! is_latest_version; then
#            max_hbck_wait_time=1900
#            if ! test -s "$hbck_log"; then
#                docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
#                    set -euo pipefail
#                    if [ -n "${DEBUG:-}" ]; then
#                        set -x
#                    fi
#                    export JAVA_HOME=/usr
#                    echo "dumping hbck log to /tmp inside container:"
#                    echo
#                    echo "retrying up to $max_hbck_wait_time secs until hdfs hbck detects corrupt files / missing blocks:"
#                    SECONDS=0
#                    while true; do
#                        # for some reason this gives a non-zero exit code, check output instead
#                        hdfs hbck / &> /tmp/hbase-hbck.log.tmp || :
#                        #tail -n 30 /tmp/hbase-hbck.log.tmp | tee /tmp/hbase-hbck.log
#                        mv -fv /tmp/hbase-hbck.log{.tmp,}
#                        grep 'CORRUPT' /tmp/hbase-hbck.log && break
#                        echo "CORRUPT not found in /tmp/hbase-hbck.log yet (waited \$SECONDS secs)"
#                        if [ "\$SECONDS" -gt "$max_hbck_wait_time" ]; then
#                            echo "HBase hbck CORRUPTION NOT DETECTED WITHIN $max_hbck_wait_time SECS!!! ABORTING..."
#                            exit 1
#                        fi
#                        sleep 1
#                    done
#                    exit 0
#EOF
#                echo
#                hr
#                dump_fsck_log "$fsck_log"
#                # TODO: add hbck failure test inside container here
#                hr
#            fi
#        fi
#    fi
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count HBase tests"
    hr
    # will return further above and not use this
    #[ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
    echo
}

run_test_versions HBase

if is_CI; then
    docker_image_cleanup
    echo
fi
