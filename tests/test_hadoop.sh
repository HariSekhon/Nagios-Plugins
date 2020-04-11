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
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/.."

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "H a d o o p"

export HADOOP_VERSIONS="${*:-${HADOOP_VERSIONS:-2.2 2.3 2.4 2.5 2.6 2.7 2.8 2.9 latest}}"

HADOOP_HOST="${DOCKER_HOST:-${HADOOP_HOST:-${HOST:-localhost}}}"
HADOOP_HOST="${HADOOP_HOST##*/}"
HADOOP_HOST="${HADOOP_HOST%%:*}"
export HADOOP_HOST
# don't need these each script should fall back to using HADOOP_HOST secondary if present
#export HADOOP_NAMENODE_HOST="$HADOOP_HOST"
#export HADOOP_DATANODE_HOST="$HADOOP_HOST"
#export HADOOP_YARN_RESOURCE_MANAGER_HOST="$HADOOP_HOST"
#export HADOOP_YARN_NODE_MANAGER_HOST="$HADOOP_HOST"
export HADOOP_NAMENODE_PORT_DEFAULT="50070"
export HADOOP_DATANODE_PORT_DEFAULT="50075"
export HADOOP_YARN_RESOURCE_MANAGER_PORT_DEFAULT="8088"
export HADOOP_YARN_NODE_MANAGER_PORT_DEFAULT="8042"
#export HADOOP_PORTS="8042 8088 50010 50020 50070 50075 50090"

# not used any more, see instead tests/docker/hadoop-docker-compose.yml
#export DOCKER_IMAGE="harisekhon/hadoop-dev"

# still used by docker_exec() function below, must align with what is set in tests/docker/common.yml
export DOCKER_MOUNT_DIR="/pl"

startupwait 90

check_docker_available

trap_debug_env hadoop

dump_fsck_log(){
    local fsck_log="$1"
    if ! is_latest_version; then
        if ! test -s "$fsck_log"; then
            echo "copying NEW $fsck_log from Hadoop $version container:"
            docker cp "$DOCKER_CONTAINER":/tmp/hdfs-fsck.log "$fsck_log"
            echo "adding new $fsck_log to git:"
            # .log paths are excluded, must -f or this will fail
            git add -f "$fsck_log"
            hr
        fi
    fi
}

test_hadoop(){
    local version="$1"
    section2 "Setting up Hadoop $version test container"
    # reset state as things like checkpoint age, blocks counts and job states, no history, succeeded etc depend on state
    docker-compose down || :
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    if [ "${version:0:1}" = 3 ]; then
        local export HADOOP_NAMENODE_PORT_DEFAULT=9870
        local export HADOOP_DATANODE_PORT_DEFAULT=9868
    fi
    echo "getting Hadoop dynamic port mappings:"
    # let it use default port which should go via haproxy, testing haproxy config at the same time as the plugins
    #docker_compose_port HADOOP_NAMENODE_PORT "HDFS NN"
    #local export HADOOP_NAMENODE_PORT="$(COMPOSE_PROJECT_NAME=nagios-plugins docker-compose -f "$srcdir/tests/docker/hadoop-docker-compose.yml" port hadoop-haproxy "$HADOOP_NAMENODE_PORT")"
    echo -n "HADOOP_NAMENODE_HAPROXY_PORT => "
    HADOOP_NAMENODE_PORT="$(docker-compose port hadoop-haproxy "$HADOOP_NAMENODE_PORT_DEFAULT" | sed 's/.*://')"
    export HADOOP_NAMENODE_PORT
    echo "$HADOOP_NAMENODE_PORT"
    docker_compose_port HADOOP_DATANODE_PORT "HDFS DN"
    docker_compose_port HADOOP_YARN_RESOURCE_MANAGER_PORT "Yarn RM"
    docker_compose_port HADOOP_YARN_NODE_MANAGER_PORT "Yarn NM"
    export HADOOP_PORTS="$HADOOP_NAMENODE_PORT $HADOOP_DATANODE_PORT $HADOOP_YARN_RESOURCE_MANAGER_PORT $HADOOP_YARN_NODE_MANAGER_PORT"
    hr
    # want splitting
    # shellcheck disable=SC2086
    when_ports_available "$HADOOP_HOST" $HADOOP_PORTS
    hr
    # needed for version tests, also don't return container to user before it's ready if NOTESTS
    # also, do this wait before HDFS setup to give datanodes time to come online to copy the file too
    echo "waiting for NN dfshealth page to come up:"
    if [[ "$version" =~ ^2\.[2-4]$ ]]; then
        when_url_content "$HADOOP_HOST:$HADOOP_NAMENODE_PORT/dfshealth.jsp" 'Hadoop NameNode'
        hr
        echo "waiting for DN page to come up:"
        # Hadoop 2.2 is broken, just check for WEB-INF, 2.3 redirects so check for url
        when_url_content "$HADOOP_HOST:$HADOOP_DATANODE_PORT" 'WEB-INF|url=dataNodeHome.jsp'
    else
        when_url_content "$HADOOP_HOST:$HADOOP_NAMENODE_PORT/dfshealth.html" 'NameNode Journal Status'
        hr
        echo "waiting for DN page to come up:"
        # Hadoop 2.8 uses /datanode.html but this isn't available on older versions eg. 2.6 so change the regex to find the redirect in 2.8 instead
        when_url_content "$HADOOP_HOST:$HADOOP_DATANODE_PORT" 'DataNode on|url=datanode\.html'
    fi
    hr
    echo "waiting for RM cluster page to come up:"
    RETRY_INTERVAL=2 when_url_content "$HADOOP_HOST:$HADOOP_YARN_RESOURCE_MANAGER_PORT/ws/v1/cluster" resourceManager
    hr
    echo "waiting for NM node page to come up:"
    # Hadoop 2.8 content = NodeManager information
    when_url_content "$HADOOP_HOST:$HADOOP_YARN_NODE_MANAGER_PORT/node" 'Node Manager Version|NodeManager information'
    hr
    echo "setting up HDFS for tests:"
    #docker-compose exec "$DOCKER_SERVICE" /bin/bash <<-EOF
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
        set -euo pipefail
        if [ -n "${DEBUG:-}" ]; then
            set -x
        fi
        export JAVA_HOME=/usr
        echo "leaving safe mode"
        hdfs dfsadmin -safemode leave
        echo "removing old hdfs file /tmp/test.txt if present"
        hdfs dfs -rm -f /tmp/test.txt &>/dev/null || :
        echo "creating test hdfs file /tmp/test.txt"
        echo content | hdfs dfs -put - /tmp/test.txt
        # if using wrong port like 50075 ot 50010 then you'll get this exception
        # triggerBlockReport error: java.io.IOException: Failed on local exception: com.google.protobuf.InvalidProtocolBufferException: Protocol message end-group tag did not match expected tag.; Host Details : local host is: "94bab7680584/172.19.0.2"; destination host is: "localhost":50075;
        # this doesn't help get Total Blocks in /blockScannerReport for ./check_hadoop_datanode_blockcount.pl, looks like that information is simply not exposed like that any more
        #hdfs dfsadmin -triggerBlockReport localhost:50020
        echo "dumping fsck log to /tmp inside container:"
        hdfs fsck / &> /tmp/hdfs-fsck.log.tmp
        tail -n30 /tmp/hdfs-fsck.log.tmp > /tmp/hdfs-fsck.log
        exit 0
EOF
    echo
    hr
    local data_dir="tests/data"
    local fsck_log="$data_dir/hdfs-fsck-$version.log"
    if ! is_latest_version; then
        dump_fsck_log "$fsck_log"
    fi
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if is_latest_version; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version
        version="$(dockerhub_latest_version hadoop-dev)"
        # 2.8.2 => 2.8 so that $version matches hdfs-fsck-2.8.log for check_hadoop_hdfs_fsck.pl check further down
        version="${version%.*}"
        echo "expecting version '$version'"
    fi
    hr
    # docker-compose exec returns $'hostname\r' but not in shell
    hostname="$(docker-compose exec "$DOCKER_SERVICE" hostname | tr -d '$\r')"
    if [ -z "$hostname" ]; then
        echo 'Failed to determine hostname of container via docker-compose exec, cannot continue with tests!'
        exit 1
    fi
    echo "determined hostname to be '$hostname'"
    hr

    run ./check_hadoop_namenode_version.py -v -e "$version"

    run_fail 2 ./check_hadoop_namenode_version.py -v -e "fail-version"

    run_conn_refused ./check_hadoop_namenode_version.py -v -e "$version"

    run ./check_hadoop_datanode_version.py -v -e "$version"

    run_fail 2 ./check_hadoop_datanode_version.py -v -e "fail-version"

    run_conn_refused ./check_hadoop_datanode_version.py -v -e "$version"

    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    run "$perl" -T ./check_hadoop_datanode_version.pl --node "$hostname" -v -e "$version"

    run_conn_refused "$perl" -T ./check_hadoop_datanode_version.pl --node "$hostname" -v -e "$version"

    run "$perl" -T ./check_hadoop_yarn_resource_manager_version.pl -v -e "$version"

    run_fail 2 "$perl" -T ./check_hadoop_yarn_resource_manager_version.pl -v -e "fail-version"

    run_conn_refused "$perl" -T ./check_hadoop_yarn_resource_manager_version.pl -v -e "$version"

    # TODO: add node manager version test

    docker_exec check_hadoop_balance.pl -w 5 -c 10 --hadoop-bin /hadoop/bin/hdfs --hadoop-user root -t 60

    run "$perl" -T ./check_hadoop_checkpoint.pl

    run_conn_refused "$perl" -T ./check_hadoop_checkpoint.pl

    echo "testing failure of checkpoint time:"
    #if ! [[ "$version" =~ ^2\.[23]$ ]]; then
    if [ "$version" = "2.2" ] || [ "$version" = "2.3" ]; then
        # for some reason this doesn't checkpoint when starting up in older versions
        run_fail 1 "$perl" -T ./check_hadoop_checkpoint.pl -w 1000000: -c 1:

        run_fail 2 "$perl" -T ./check_hadoop_checkpoint.pl -w 30000000: -c 20000000:
    else
        run_fail 1 "$perl" -T ./check_hadoop_checkpoint.pl -w 1000: -c 1:

        run_fail 2 "$perl" -T ./check_hadoop_checkpoint.pl -w 3000: -c 2000:
    fi

    run "$perl" -T ./check_hadoop_datanode_jmx.pl --all-metrics

    run_conn_refused "$perl" -T ./check_hadoop_datanode_jmx.pl --all-metrics

    run ./check_hadoop_datanodes_block_balance.py -w 5 -c 10

    run ./check_hadoop_datanodes_block_balance.py -w 5 -c 10 -v

    run_conn_refused ./check_hadoop_datanodes_block_balance.py -w 5 -c 10

    run ./check_hadoop_hdfs_balance.py -w 5 -c 10

    run ./check_hadoop_hdfs_balance.py -w 5 -c 10 -v

    run_conn_refused ./check_hadoop_hdfs_balance.py -w 5 -c 10

    run "$perl" -T ./check_hadoop_datanodes.pl

    run "$perl" -T ./check_hadoop_datanodes.pl --stale-threshold 0

    run_conn_refused "$perl" -T ./check_hadoop_datanodes.pl

    run ./check_hadoop_datanode_last_contact.py --node "$hostname"

    if [[ "$version" =~ ^2\.[0-6]$ ]]; then
        echo "checking specifying datanode with port suffix in Hadoop < 2.7 is not found:"
        run_fail 3 ./check_hadoop_datanode_last_contact.py --node "$hostname:50010"
    else
        echo "checking we can specify datanode with port suffix in Hadoop 2.7+:"
        run ./check_hadoop_datanode_last_contact.py --node "$hostname:50010"
    fi

    run_fail 3 ./check_hadoop_datanode_last_contact.py --node "nonexistentnode"

    run_conn_refused ./check_hadoop_datanode_last_contact.py --node "$hostname"

    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hadoop --hadoop-user root --hdfs-space -w 80 -c 90 -t 20

    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --replication -w 1 -c 1 -t 20

    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --balance -w 5 -c 10 -t 20

    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --nodes-available -w 1 -c 1 -t 20

    # on a real cluster thresholds should be set to millions+, no defaults as must be configured based on NN heap allocated
    run ./check_hadoop_hdfs_total_blocks.py -w 10 -c 20

    run_conn_refused ./check_hadoop_hdfs_total_blocks.py -w 10 -c 20

    echo "testing failure scenarios:"
    run_fail 1 ./check_hadoop_hdfs_total_blocks.py -w 0 -c 4

    run_fail 2 ./check_hadoop_hdfs_total_blocks.py -w 0 -c 0

    # only check logs for each version as there is no latest fsck log as it would be a duplicate of the highest version number
    echo "version = $version"
    if ! is_latest_version; then
        run "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log"

        run "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --stats

        run_fail 1 "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --last-fsck -w 1 -c 999999999

        run_fail 2 "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --last-fsck -w 1 -c 1

        run "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --max-blocks -w 1 -c 2

        run_fail 1 "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --max-blocks -w 0 -c 1

        run_fail 2 "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --max-blocks -w 0 -c 0
    fi

    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log

    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --stats

    echo "checking hdfs fsck failure scenarios:"
    ERRCODE=1 docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --last-fsck -w 1 -c 200000000

    ERRCODE=2 docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --last-fsck -w 1 -c 1

    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 1 -c 2

    ERRCODE=1 docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 0 -c 1

    ERRCODE=2 docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 0 -c 0

    # TODO: FIXME: this shouldn't require docker module to be installed as don't use docker nagios plugin class
    #docker exec $DOCKER_CONTAINER pip install docker
    ERRCODE="0 1" docker_exec check_hadoop_hdfs_rack_resilience.py

    run "$perl" -T ./check_hadoop_hdfs_space.pl

    run_conn_refused "$perl" -T ./check_hadoop_hdfs_space.pl

    run ./check_hadoop_hdfs_space.py

    run_conn_refused ./check_hadoop_hdfs_space.py

    # XXX: these ports must be left as this plugin is generic and has no default port, nor does it pick up any environment variables more specific than $PORT
    run "$perl" -T ./check_hadoop_jmx.pl --all -P "$HADOOP_NAMENODE_PORT"

    run "$perl" -T ./check_hadoop_jmx.pl --all -P "$HADOOP_DATANODE_PORT"

    run "$perl" -T ./check_hadoop_jmx.pl --all -P "$HADOOP_YARN_RESOURCE_MANAGER_PORT"

    run "$perl" -T ./check_hadoop_jmx.pl --all -P "$HADOOP_YARN_NODE_MANAGER_PORT"

    run_conn_refused "$perl" -T ./check_hadoop_jmx.pl --all

    run ./check_hadoop_namenode_failed_namedirs.py

    run ./check_hadoop_namenode_failed_namedirs.py -v

    run_conn_refused ./check_hadoop_namenode_failed_namedirs.py

    run "$perl" -T ./check_hadoop_namenode_heap.pl

    run "$perl" -T ./check_hadoop_namenode_heap.pl --non-heap

    run_conn_refused "$perl" -T ./check_hadoop_namenode_heap.pl

    run "$perl" -T ./check_hadoop_namenode_jmx.pl --all-metrics

    run_conn_refused "$perl" -T ./check_hadoop_namenode_jmx.pl --all-metrics

    run_conn_refused "$perl" -T ./check_hadoop_namenode.pl -v --balance -w 5 -c 10

    run "$perl" -T ./check_hadoop_namenode_safemode.pl

    run_conn_refused "$perl" -T ./check_hadoop_namenode_safemode.pl

    if [ "$version" != "2.2" ]; then
        ERRCODE=2 run_grep "CRITICAL: namenode security enabled 'false'" "$perl" -T ./check_hadoop_namenode_security_enabled.pl
    fi

    run "$perl" -T ./check_hadoop_namenode_ha_state.pl

    run_conn_refused "$perl" -T ./check_hadoop_namenode_ha_state.pl

    run "$perl" -T ./check_hadoop_namenode_ha_state.pl --active

    run_fail 2 "$perl" -T ./check_hadoop_namenode_ha_state.pl --standby

    run "$perl" -T ./check_hadoop_replication.pl

    run_conn_refused "$perl" -T ./check_hadoop_replication.pl

    run ./check_hadoop_namenode_java_gc.py
    run ./check_hadoop_datanode_java_gc.py
    run ./check_hadoop_resource_manager_java_gc.py
    run ./check_hadoop_node_manager_java_gc.py

    run_fail 2 ./check_hadoop_namenode_java_gc.py -c 0
    run_fail 2 ./check_hadoop_datanode_java_gc.py -c 0
    run_fail 2 ./check_hadoop_resource_manager_java_gc.py -c 0
    run_fail 2 ./check_hadoop_node_manager_java_gc.py -c 0

    run_conn_refused ./check_hadoop_namenode_java_gc.py
    run_conn_refused ./check_hadoop_datanode_java_gc.py
    run_conn_refused ./check_hadoop_resource_manager_java_gc.py
    run_conn_refused ./check_hadoop_node_manager_java_gc.py

    # ================================================
    check_newer_plugins

    check_older_plugins
    hr
    # ================================================
    echo
    echo "Now checking YARN Job plugins, including running the classic MR MonteCarlo Pi job:"
    echo
    run_fail 2 ./check_hadoop_yarn_app_running.py -a '.*'

    run_conn_refused ./check_hadoop_yarn_app_running.py -a '.*'

    run_fail 2 ./check_hadoop_yarn_app_running.py -a '.*' -v

    # ================================================
    run_fail 2 ./check_hadoop_yarn_app_last_run.py -a '.*'

    run_fail 2 ./check_hadoop_yarn_app_last_run.py -a '.*' -v

    run_conn_refused ./check_hadoop_yarn_app_last_run.py -a '.*'

    # ================================================
    run ./check_hadoop_yarn_long_running_apps.py

    run ./check_hadoop_yarn_long_running_apps.py -v

    run_conn_refused ./check_hadoop_yarn_long_running_apps.py -v

    # ================================================
    echo
    echo
    run_fail 2 ./check_hadoop_yarn_app_running.py -l
    echo
    echo
    run_fail 2 ./check_hadoop_yarn_app_last_run.py -l
    echo
    echo
    run_fail 3 ./check_hadoop_yarn_queue_apps.py -l
    echo
    echo
    run_fail 3 ./check_hadoop_yarn_long_running_apps.py -l
    echo
    # ================================================
    # TODO: add pi job run and kill it to test ./check_hadoop_yarn_app_last_run.py for KILLED status
    # TODO: add teragen job run with bad preexisting output dir to test ./check_hadoop_yarn_app_last_run.py for FAILED status
    # TODO: use --include --exclude to work around the two tests
    echo "Running sample mapreduce job to test Yarn application / job based plugins against:"
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<EOF &
    echo
    echo "running mapreduce job from sample jar"
    echo
    output='&>/dev/null'
    if [ -n "${DEBUG:-}" ]; then
        output=''
        set -x
    fi
    eval hadoop jar /hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 20 20 \$output &
    set +x
    echo
    echo "triggered mapreduce job"
    echo
    disown
    exit
EOF
    hr
    echo "waiting for job to enter running state:"
    set +e
    local max_wait_job_running_secs=30
    # -a '.*' keeps getting expanded incorrectly in shell inside retry(), cannot quote inside retry() and escaping '.\*' or ".\*" doesn't work either it appears as those the backslash is passed in literally to the program
    RETRY_INTERVAL=3 retry "$max_wait_job_running_secs" ./check_hadoop_yarn_app_running.py -a "monte"
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        # Job can get stuck in Accepted state with no NM to run on if disk > 90% full it gets marked as bad dir - Docker images have been updated to permit 100% / not check disk utilization so there is more chance of this working on machines with low disk space left, eg. your laptop
        echo "FAILED: MapReduce job was not detected as running after $max_wait_job_running_secs secs (is disk >90% full?)"
        exit 1
    fi
    set -e
    hr
    echo "Checking app listings while there is an app running:"
    echo
    run_fail 3 ./check_hadoop_yarn_app_running.py -l
    echo
    echo
    run_fail 3 ./check_hadoop_yarn_queue_apps.py -l
    echo
    echo
    run_fail 3 ./check_hadoop_yarn_long_running_apps.py -l
    echo
    echo
    run ./check_hadoop_yarn_app_running.py -a '.*' -v

    run ./check_hadoop_yarn_app_running.py -a 'monte.*carlo'

    run_grep "checked 1 out of" ./check_hadoop_yarn_long_running_apps.py --include=montecarlo

    run ./check_hadoop_yarn_long_running_apps.py

    run ./check_hadoop_yarn_long_running_spark_shells.py

    run_fail 2 ./check_hadoop_yarn_long_running_apps.py -c 2

    run ./check_hadoop_yarn_queue_apps.py

    run ./check_hadoop_yarn_queue_apps.py --allow monte

    run_fail 1 ./check_hadoop_yarn_queue_apps.py --disallow monte

    run_fail 1 ./check_hadoop_yarn_queue_apps.py --allow nonmatching

    run_grep "checked 1 out of" ./check_hadoop_yarn_long_running_apps.py

    run_grep "checked 0 out of" ./check_hadoop_yarn_long_running_apps.py --queue nonexistentqueue

    run_grep "checked 1 out of" ./check_hadoop_yarn_long_running_apps.py --include='te.*carl'

    run_grep "checked 0 out of" ./check_hadoop_yarn_long_running_apps.py --include=montecarlo --exclude=m.nte

    run_grep "checked 0 out of" ./check_hadoop_yarn_long_running_apps.py --include=montecarlo --exclude-queue default

    run_grep "checked 0 out of" ./check_hadoop_yarn_long_running_apps.py --exclude=quasi

    echo "waiting for job to stop running:"
    ERRCODE=2 RETRY_INTERVAL=2 retry 100 ./check_hadoop_yarn_app_running.py -a 'monte'
    hr
    echo "Checking listing app history:"
    echo
    run_fail 3 ./check_hadoop_yarn_app_last_run.py -l

    echo
    echo "now testing last run status:"
    run ./check_hadoop_yarn_app_last_run.py -a '.*' -v

    run ./check_hadoop_yarn_app_last_run.py -a montecarlo

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_app_stats.pl

    run_conn_refused "$perl" -T ./check_hadoop_yarn_app_stats.pl

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_app_stats_queue.pl

    run_conn_refused "$perl" -T ./check_hadoop_yarn_app_stats_queue.pl

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_metrics.pl

    run_conn_refused "$perl" -T ./check_hadoop_yarn_metrics.pl

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_node_manager.pl

    run_conn_refused "$perl" -T ./check_hadoop_yarn_node_manager.pl

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_node_managers.pl -w 1 -c 1

    run_conn_refused "$perl" -T ./check_hadoop_yarn_node_managers.pl -w 1 -c 1

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_node_manager_via_rm.pl --node "$hostname"

    run_conn_refused "$perl" -T ./check_hadoop_yarn_node_manager_via_rm.pl --node "$hostname"

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_queue_capacity.pl

    run "$perl" -T ./check_hadoop_yarn_queue_capacity.pl --queue default

    run_conn_refused "$perl" -T ./check_hadoop_yarn_queue_capacity.pl

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_queue_state.pl

    run "$perl" -T ./check_hadoop_yarn_queue_state.pl --queue default

    run_conn_refused "$perl" -T ./check_hadoop_yarn_queue_state.pl

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_resource_manager_heap.pl

    run_conn_refused "$perl" -T ./check_hadoop_yarn_resource_manager_heap.pl

    # ================================================
    # returns -1 for NonHeapMemoryUsage max
    run_fail 3 "$perl" -T ./check_hadoop_yarn_resource_manager_heap.pl --non-heap

    run_conn_refused "$perl" -T ./check_hadoop_yarn_resource_manager_heap.pl --non-heap

    # ================================================

    run_conn_refused ./check_hadoop_yarn_resource_manager_ha_state.py

    # ================================================

    run "$perl" -T ./check_hadoop_yarn_resource_manager_state.pl

    run_conn_refused "$perl" -T ./check_hadoop_yarn_resource_manager_state.pl

    # ================================================
    echo "Now killing DataNode and NodeManager to run worker failure tests:"
    echo "killing datanode:"
    docker exec -ti "$DOCKER_CONTAINER" pkill -9 -f org.apache.hadoop.hdfs.server.datanode.DataNode
    echo "killing node manager:"
    docker exec -ti "$DOCKER_CONTAINER" pkill -9 -f org.apache.hadoop.yarn.server.nodemanager.NodeManager
    hr
    # ================================================
    echo "Now waiting for masters to detect worker failures:"
    echo "waiting for NameNode to detect DataNode failure:"
    ERRCODE=1 retry 30 "$perl" -T ./check_hadoop_datanodes.pl
    hr

    echo "datanodes should be in warning state at this point due to being stale with contact lag but not yet marked dead:"
    ERRCODE=1 run_grep '1 stale' "$perl" -T ./check_hadoop_datanodes.pl

    # typically 10-20 secs since last contact by this point
    run_fail 1 ./check_hadoop_datanode_last_contact.py --node "$hostname" -w 5

    run_fail 2 ./check_hadoop_datanode_last_contact.py --node "$hostname" -c 5

    # ================================================
    # TODO: submit job to get stuck in ACCEPTED state and test yarn apps plugins again
    echo "waiting for Yarn Resource Manager to detect NodeManager failure:"
    ERRCODE=1 RETRY_INTERVAL=3 retry 60 "$perl" -T ./check_hadoop_yarn_node_managers.pl -w 0 -c 1
    hr
    ERRCODE=2 retry 10 "$perl" -T ./check_hadoop_yarn_node_manager_via_rm.pl --node "$hostname"
    hr
    # ================================================
    # API endpoint not available in Hadoop 2.2
    if [ "$version" != "2.2" ]; then
        # still passes as it's only metadata
        # the check for corrupt / missing blocks / files should catch the fact that the underlying data is offline
        docker_exec check_hadoop_hdfs_file_webhdfs.pl -H localhost -p /tmp/test.txt --owner root --group supergroup --replication 1 --size 8 --last-accessed 600 --last-modified 600 --blockSize 134217728

        # run inside Docker container so it can resolve redirect to DN
        ERRCODE=2 docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost
    fi

    run_fail 2 "$perl" -T ./check_hadoop_yarn_node_manager.pl

    # ================================================

    run_fail 1 "$perl" -T ./check_hadoop_yarn_node_managers.pl -w 0 -c 1

    run_fail 2 "$perl" -T ./check_hadoop_yarn_node_managers.pl -w 0 -c 0

    # ================================================

    run_fail 2 "$perl" -T ./check_hadoop_yarn_node_manager_via_rm.pl --node "$hostname"

    # ================================================

    echo "Now waiting on datanode to be marked as dead:"
    # NN 2 * heartbeatRecheckInterval (10) + 10 * 1000 * heartbeatIntervalSeconds == 50 secs
    ERRCODE=2 retry 50 "$perl" -T ./check_hadoop_datanodes.pl -c 0
    hr

    run_fail 2 "$perl" -T ./check_hadoop_datanodes.pl -c 0

    # ================================================
    # stuff from here will must be tested after worker
    # thresholds have been exceeded, relying on latch
    # from retry on datanodes above
    # ================================================
    echo "check datanode last contact returns critical if node is marked as dead regardless of the thresholds:"
    run_fail 2 ./check_hadoop_datanode_last_contact.py --node "$hostname" -w 999999999 -c 9999999999

    run_fail 2 ./check_hadoop_datanodes_block_balance.py -w 5 -c 10

    run_fail 2 ./check_hadoop_hdfs_balance.py -w 5 -c 10 -v

    # space will show 0% but datanodes < 1 should trigger warning
    ERRCODE=1 docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hadoop --hadoop-user root --hdfs-space -w 80 -c 90 -t 20

    # XXX: doesn't detect missing blocks yet - revisit
    #ERRCODE=2 docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --replication -w 1 -c 1 -t 20

    ERRCODE=1 docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --balance -w 5 -c 10 -t 20

    ERRCODE=2 docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --nodes-available -w 1 -c 1 -t 20

    # API field not available in Hadoop 2.2
    if [ "$version" != "2.2" ]; then
        ERRCODE=2 retry 20 ./check_hadoop_hdfs_corrupt_files.py -v
        hr

        run_fail 2 ./check_hadoop_hdfs_corrupt_files.py -v

        run_fail 2 ./check_hadoop_hdfs_corrupt_files.py -vv

        # still passes as it's only metadata
        docker_exec check_hadoop_hdfs_file_webhdfs.pl -H localhost -p /tmp/test.txt --owner root --group supergroup --replication 1 --size 8 --last-accessed 600 --last-modified 600 --blockSize 134217728

        # run inside Docker container so it can resolve redirect to DN
        ERRCODE=2 docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost
    fi

    ERRCODE=2 retry 20 "$perl" -T ./check_hadoop_hdfs_space.pl

    run_fail 2 "$perl" -T ./check_hadoop_hdfs_space.pl

    run_fail 2 ./check_hadoop_hdfs_space.py

    run_fail 2 "$perl" -T ./check_hadoop_replication.pl

    if [[ "$version" =~ ^2\.[0-6]$ ]]; then
        echo
        echo "Now running legacy checks against failure scenarios:"
        echo
        run_fail 3 "$perl" -T ./check_hadoop_datanodes_block_balance.pl -w 5 -c 10

        run_fail 3 "$perl" -T ./check_hadoop_datanodes_blockcounts.pl

        run_fail 1 "$perl" -T ./check_hadoop_namenode.pl -v --balance -w 5 -c 10

        run_fail 2 "$perl" -T ./check_hadoop_namenode.pl -v --hdfs-space

        run_fail 2 "$perl" -T ./check_hadoop_namenode.pl -v --replication -w 10 -c 20

        run_fail 3 "$perl" -T ./check_hadoop_namenode.pl -v --datanode-blocks

        run_fail 3 "$perl" -T ./check_hadoop_namenode.pl --datanode-block-balance -w 5 -c 20

        run_fail 3 "$perl" -T ./check_hadoop_namenode.pl --datanode-block-balance -w 5 -c 20 -v

        run_fail 1 "$perl" -T ./check_hadoop_namenode.pl -v --node-count -w 1 -c 0

        echo "checking node count (expecting critical < 1 nodes)"
        run_fail 2 "$perl" -t ./check_hadoop_namenode.pl -v --node-count -w 2 -c 1

        run_fail 2 "$perl" -T ./check_hadoop_namenode.pl -v --node-list "$hostname"
    fi

    # This takes ages and we aren't going to git commit the collected log from Jenkins or Travis CI
    # so don't bother running on there are it would only time out the builds anyway
    local fsck_fail_log="$data_dir/hdfs-fsck-fail-$version.log"
    if ! is_CI; then
        if ! is_latest_version; then
            max_fsck_wait_time=30
            if ! test -s "$fsck_fail_log"; then
                echo "getting new hdfs failure fsck:"
                #docker-compose exec "$DOCKER_SERVICE" /bin/bash <<-EOF
                docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
                    set -euo pipefail
                    if [ -n "${DEBUG:-}" ]; then
                        set -x
                    fi
                    export JAVA_HOME=/usr
                    echo "dumping fsck log to /tmp inside container:"
                    echo
                    echo "retrying up to $max_fsck_wait_time secs until hdfs fsck detects corrupt files / missing blocks:"
                    SECONDS=0
                    while true; do
                        # for some reason this gives a non-zero exit code, check output instead
                        hdfs fsck / &> /tmp/hdfs-fsck.log.tmp || :
                        #tail -n 30 /tmp/hdfs-fsck.log.tmp | tee /tmp/hdfs-fsck.log
                        mv -fv /tmp/hdfs-fsck.log{.tmp,}
                        grep 'CORRUPT' /tmp/hdfs-fsck.log && break
                        echo "CORRUPT not found in /tmp/hdfs-fsck.log yet (waited \$SECONDS secs)"
                        if [ "\$SECONDS" -gt "$max_fsck_wait_time" ]; then
                            echo "HDFS FSCK CORRUPTION NOT DETECTED WITHIN $max_fsck_wait_time SECS!!! ABORTING..."
                            exit 1
                        fi
                        sleep 1
                    done
                    exit 0
EOF
                echo
                hr
                dump_fsck_log "$fsck_fail_log"
                ERRCODE=2 docker_exec check_hadoop_hdfs_fsck.pl -f "/tmp/hdfs-fsck.log" # --last-fsck -w 1 -c 200000000

            fi
        fi
    fi
    if [ -f "$fsck_fail_log" ]; then
        run_fail 2 "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_fail_log"

        run_fail 2 "$perl" -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_fail_log" --stats
    fi
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Hadoop tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
    echo
}

check_newer_plugins(){
    echo
    echo "Now checking plugins that only work on newer versions of Hadoop:"
    echo
    if [ "$version" != "2.2" ]; then
        # corrupt fields field is not available in older versions of Hadoop
        run ./check_hadoop_hdfs_corrupt_files.py

        # WebHDFS API endpoint not present in Hadoop 2.2
        # run inside Docker container so it can resolve redirect to DN
        docker_exec check_hadoop_hdfs_file_webhdfs.pl -H localhost -p /tmp/test.txt --owner root --group supergroup --replication 1 --size 8 --last-accessed 600 --last-modified 600 --blockSize 134217728

        # run inside Docker container so it can resolve redirect to DN
        docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost

        ERRCODE=2 docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost -P "$wrong_port"

        # Yarn RM HA state field not available in older versions of Hadoop
        run ./check_hadoop_yarn_resource_manager_ha_state.py

        run ./check_hadoop_yarn_resource_manager_ha_state.py --active

        run_fail 2 ./check_hadoop_yarn_resource_manager_ha_state.py --standby
    fi
}

check_older_plugins(){
    echo
    echo "Now checking plugins that only work on older versions of Hadoop:"
    echo
    # TODO: write replacement python plugins for this stuff
    # XXX: Hadoop doesn't expose this information in the same way any more via dfshealth.jsp so these plugins are end of life with Hadoop 2.6
    if [[ "$version" =~ ^2\.[0-6]$ ]]; then
        # gets 404 not found on newer Hadoop versions
        run "$perl" -T ./check_hadoop_datanode_blockcount.pl

        run_conn_refused "$perl" -T ./check_hadoop_datanode_blockcount.pl

        run "$perl" -T ./check_hadoop_datanodes_block_balance.pl -w 5 -c 10

        run "$perl" -T ./check_hadoop_datanodes_block_balance.pl -w 5 -c 10 -v

        run_conn_refused "$perl" -T ./check_hadoop_datanodes_block_balance.pl -w 5 -c 10

        run "$perl" -T ./check_hadoop_datanodes_blockcounts.pl

        run_conn_refused "$perl" -T ./check_hadoop_datanodes_blockcounts.pl

        # on a real cluster thresholds should be set to millions+, no defaults as must be configured based on NN heap allocated
        # XXX: Total Blocks are not available via blockScannerReport from Hadoop 2.7
        run "$perl" -T ./check_hadoop_hdfs_total_blocks.pl -w 10 -c 20

        run_conn_refused "$perl" -T ./check_hadoop_hdfs_total_blocks.pl -w 10 -c 20

        echo "testing failure scenarios:"
        run_fail 1 "$perl" -T ./check_hadoop_hdfs_total_blocks.pl -w 0 -c 4

        run_fail 2 "$perl" -T ./check_hadoop_hdfs_total_blocks.pl -w 0 -c 0

        run_conn_refused "$perl" -T ./check_hadoop_hdfs_total_blocks.pl -w 0 -c 1

        run "$perl" -T ./check_hadoop_namenode.pl -v --balance -w 5 -c 10

        run "$perl" -T ./check_hadoop_namenode.pl -v --hdfs-space

        run "$perl" -T ./check_hadoop_namenode.pl -v --replication -w 10 -c 20

        run "$perl" -T ./check_hadoop_namenode.pl -v --datanode-blocks

        run "$perl" -T ./check_hadoop_namenode.pl --datanode-block-balance -w 5 -c 20

        run "$perl" -T ./check_hadoop_namenode.pl --datanode-block-balance -w 5 -c 20 -v

        run "$perl" -T ./check_hadoop_namenode.pl -v --node-count -w 1 -c 1

        echo "checking node count (expecting warning < 2 nodes):"
        run_fail 1 "$perl" -t ./check_hadoop_namenode.pl -v --node-count -w 2 -c 1

        echo "checking node count (expecting critical < 2 nodes):"
        run_fail 2 "$perl" -t ./check_hadoop_namenode.pl -v --node-count -w 2 -c 2

        run "$perl" -T ./check_hadoop_namenode.pl -v --node-list "$hostname"

        run "$perl" -T ./check_hadoop_namenode.pl -v --heap-usage -w 80 -c 90

        echo "checking we can trigger warning on heap usage:"
        run_fail 1 "$perl" -T ./check_hadoop_namenode.pl -v --heap-usage -w 1 -c 90

        echo "checking we can trigger critical on heap usage:"
        run_fail 2 "$perl" -T ./check_hadoop_namenode.pl -v --heap-usage -w 0 -c 1

        run "$perl" -T ./check_hadoop_namenode.pl -v --non-heap-usage -w 80 -c 90

        # these won't trigger as NN has no max non-heap
#        echo "checking we can trigger warning on non-heap usage"
#        set +e
#        "$perl" -T ./check_hadoop_namenode.pl - P"$HADOOP_NAMENODE_PORT" -v --non-heap-usage -w 1 -c 90
#        check_exit_code 1
#        hr
#        echo "checking we can trigger critical on non-heap usage"
#        set +e
#        "$perl" -T ./check_hadoop_namenode.pl -P "$HADOOP_NAMENODE_PORT" -v --non-heap-usage -w 0 -c 1
#        check_exit_code 2
#        set -e
#        hr
    fi
}

run_test_versions Hadoop

if is_CI; then
    docker_image_cleanup
    echo
fi
