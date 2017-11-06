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

. "$srcdir/utils.sh"

section "H a d o o p"

export HADOOP_VERSIONS="${@:-${HADOOP_VERSIONS:-latest 2.2 2.3 2.4 2.5 2.6 2.7 2.8}}"

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
export MNTDIR="/pl"

startupwait 30

check_docker_available

trap_debug_env hadoop

docker_exec(){
    #docker-compose exec "$DOCKER_SERVICE" $MNTDIR/$@
    run docker exec "$DOCKER_CONTAINER" "$MNTDIR/$@"
}

dump_fsck_log(){
    local fsck_log="$1"
    if [ "$version" != "latest" ]; then
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
    if is_CI || [ -n "${DOCKER_PULL:-}" ]; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    echo "getting Hadoop dynamic port mappings:"
    docker_compose_port HADOOP_NAMENODE_PORT "HDFS NN"
    docker_compose_port HADOOP_DATANODE_PORT "HDFS DN"
    docker_compose_port HADOOP_YARN_RESOURCE_MANAGER_PORT "Yarn RM"
    docker_compose_port HADOOP_YARN_NODE_MANAGER_PORT "Yarn NM"
    export HADOOP_PORTS="$HADOOP_NAMENODE_PORT $HADOOP_DATANODE_PORT $HADOOP_YARN_RESOURCE_MANAGER_PORT $HADOOP_YARN_NODE_MANAGER_PORT"
    hr
    when_ports_available "$HADOOP_HOST" $HADOOP_PORTS
    hr
    # needed for version tests, also don't return container to user before it's ready if NOTESTS
    # also, do this wait before HDFS setup to give datanodes time to come online to copy the file too
    echo "waiting for NN dfshealth page to come up:"
    if [[ "$version" =~ ^2\.[2-4]$ ]]; then
        when_url_content "$HADOOP_HOST:$HADOOP_NAMENODE_PORT/dfshealth.jsp" 'Hadoop NameNode'
        echo "waiting for DN page to come up:"
        hr
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
    echo "setting up HDFS for tests"
    #docker-compose exec "$DOCKER_SERVICE" /bin/bash <<-EOF
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
        set -eu
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
        hdfs fsck / &> /tmp/hdfs-fsck.log.tmp && tail -n30 /tmp/hdfs-fsck.log.tmp > /tmp/hdfs-fsck.log
        exit 0
EOF
    echo
    hr
    data_dir="tests/data"
    local fsck_log="$data_dir/hdfs-fsck-$version.log"
    dump_fsck_log "$fsck_log"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        local version="$(dockerhub_latest_version hadoop-dev)"
        # 2.8.2 => 2.8 so that $version matches hdfs-fsck-2.8.log for check_hadoop_hdfs_fsck.pl check further down
        version="${version%.*}"
        echo "expecting version '$version'"
    fi
    # docker-compose exec returns $'hostname\r' but not in shell
    hostname="$(docker-compose exec "$DOCKER_SERVICE" hostname | tr -d '$\r')"
    if [ -z "$hostname" ]; then
        echo 'Failed to determine hostname of container via docker-compose exec, cannot continue with tests!'
        exit 1
    fi
    run ./check_hadoop_namenode_version.py -v -e "$version"
    hr
    run_fail 2 ./check_hadoop_namenode_version.py -v -e "fail-version"
    hr
    run_conn_refused ./check_hadoop_namenode_version.py -v -e "$version"
    hr
    run ./check_hadoop_datanode_version.py -v -e "$version"
    hr
    run_fail 2 ./check_hadoop_datanode_version.py -v -e "fail-version"
    hr
    run_conn_refused ./check_hadoop_datanode_version.py -v -e "$version"
    hr
    run $perl -T ./check_hadoop_datanode_version.pl --node "$hostname" -v -e "$version"
    hr
    run_conn_refused $perl -T ./check_hadoop_datanode_version.pl --node "$hostname" -v -e "$version"
    hr
    run $perl -T ./check_hadoop_yarn_resource_manager_version.pl -v -e "$version"
    hr
    run_fail 2 $perl -T ./check_hadoop_yarn_resource_manager_version.pl -v -e "fail-version"
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_resource_manager_version.pl -v -e "$version"
    hr
    # TODO: add node manager version test
    hr
    docker_exec check_hadoop_balance.pl -w 5 -c 10 --hadoop-bin /hadoop/bin/hdfs --hadoop-user root -t 60
    hr
    run $perl -T ./check_hadoop_checkpoint.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_checkpoint.pl
    hr
    echo "testing failure of checkpoint time:"
    #if ! [[ "$version" =~ ^2\.[23]$ ]]; then
    if [ "$version" = "2.2" -o "$version" = "2.3" ]; then
        # for some reason this doesn't checkpoint when starting up in older versions
        run_fail 1 $perl -T ./check_hadoop_checkpoint.pl -w 1000000: -c 1:
        hr
        run_fail 2 $perl -T ./check_hadoop_checkpoint.pl -w 30000000: -c 20000000:
    else
        run_fail 1 $perl -T ./check_hadoop_checkpoint.pl -w 1000: -c 1:
        hr
        run_fail 2 $perl -T ./check_hadoop_checkpoint.pl -w 3000: -c 2000:
    fi
    hr
    run $perl -T ./check_hadoop_datanode_jmx.pl --all-metrics
    hr
    run_conn_refused $perl -T ./check_hadoop_datanode_jmx.pl --all-metrics
    hr
    run ./check_hadoop_datanodes_block_balance.py -w 5 -c 10
    hr
    run ./check_hadoop_datanodes_block_balance.py -w 5 -c 10 -v
    hr
    run_conn_refused ./check_hadoop_datanodes_block_balance.py -w 5 -c 10
    hr
    run ./check_hadoop_hdfs_balance.py -w 5 -c 10
    hr
    run ./check_hadoop_hdfs_balance.py -w 5 -c 10 -v
    hr
    run_conn_refused ./check_hadoop_hdfs_balance.py -w 5 -c 10
    hr
    run $perl -T ./check_hadoop_datanodes.pl
    hr
    run $perl -T ./check_hadoop_datanodes.pl --stale-threshold 0
    hr
    run_conn_refused $perl -T ./check_hadoop_datanodes.pl
    hr
    run ./check_hadoop_datanode_last_contact.py --node "$hostname"
    hr
    if [[ "$version" =~ ^2\.[0-6]$ ]]; then
        echo "checking specifying datanode with port suffix in Hadoop < 2.7 is not found:"
        run_fail 3 ./check_hadoop_datanode_last_contact.py --node "$hostname:50010"
    else
        echo "checking we can specify datanode with port suffix in Hadoop 2.7+:"
        run ./check_hadoop_datanode_last_contact.py --node "$hostname:50010"
    fi
    hr
    run_fail 3 ./check_hadoop_datanode_last_contact.py --node "nonexistentnode"
    hr
    run_conn_refused ./check_hadoop_datanode_last_contact.py --node "$hostname"
    hr
    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hadoop --hadoop-user root --hdfs-space -w 80 -c 90 -t 20
    hr
    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --replication -w 1 -c 1 -t 20
    hr
    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --balance -w 5 -c 10 -t 20
    hr
    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --nodes-available -w 1 -c 1 -t 20
    hr
    # on a real cluster thresholds should be set to millions+, no defaults as must be configured based on NN heap allocated
    run ./check_hadoop_hdfs_total_blocks.py -w 10 -c 20
    hr
    run_conn_refused ./check_hadoop_hdfs_total_blocks.py -w 10 -c 20
    hr
    echo "testing failure scenarios:"
    run_fail 1 ./check_hadoop_hdfs_total_blocks.py -w 0 -c 4
    hr
    run_fail 2 ./check_hadoop_hdfs_total_blocks.py -w 0 -c 0
    hr
    # only check logs for each version as there is no latest fsck log as it would be a duplicate of the highest version number
    if [ "$version" != "latest" -a "$version" != ".*" ]; then
        run $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log"
        hr
        run $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --stats
        hr
        run_fail 1 $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --last-fsck -w 1 -c 999999999
        hr
        run_fail 2 $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --last-fsck -w 1 -c 1
        hr
        run $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --max-blocks -w 1 -c 2
        hr
        run_fail 1 $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --max-blocks -w 0 -c 1
        hr
        run_fail 2 $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --max-blocks -w 0 -c 0
        hr
    fi
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log
    hr
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --stats
    hr
    echo "checking hdfs fsck failure scenarios:"
    ERRCODE=1 docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --last-fsck -w 1 -c 200000000
    hr
    ERRCODE=2 docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --last-fsck -w 1 -c 1
    hr
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 1 -c 2
    hr
    ERRCODE=1 docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 0 -c 1
    hr
    ERRCODE=2 docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 0 -c 0
    hr
    run $perl -T ./check_hadoop_hdfs_space.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_hdfs_space.pl
    hr
    run ./check_hadoop_hdfs_space.py
    hr
    run_conn_refused ./check_hadoop_hdfs_space.py
    hr
    # XXX: these ports must be left as this plugin is generic and has no default port, nor does it pick up any environment variables more specific than $PORT
    run $perl -T ./check_hadoop_jmx.pl --all -P "$HADOOP_NAMENODE_PORT"
    hr
    run $perl -T ./check_hadoop_jmx.pl --all -P "$HADOOP_DATANODE_PORT"
    hr
    run $perl -T ./check_hadoop_jmx.pl --all -P "$HADOOP_YARN_RESOURCE_MANAGER_PORT"
    hr
    run $perl -T ./check_hadoop_jmx.pl --all -P "$HADOOP_YARN_NODE_MANAGER_PORT"
    hr
    run_conn_refused $perl -T ./check_hadoop_jmx.pl --all
    hr
    run ./check_hadoop_namenode_failed_namedirs.py
    hr
    run ./check_hadoop_namenode_failed_namedirs.py -v
    hr
    run_conn_refused ./check_hadoop_namenode_failed_namedirs.py
    hr
    run $perl -T ./check_hadoop_namenode_heap.pl
    hr
    run $perl -T ./check_hadoop_namenode_heap.pl --non-heap
    hr
    run_conn_refused $perl -T ./check_hadoop_namenode_heap.pl
    hr
    run $perl -T ./check_hadoop_namenode_jmx.pl --all-metrics
    hr
    run_conn_refused $perl -T ./check_hadoop_namenode_jmx.pl --all-metrics
    hr
    run_conn_refused $perl -T ./check_hadoop_namenode.pl -v --balance -w 5 -c 10
    hr
    run $perl -T ./check_hadoop_namenode_safemode.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_namenode_safemode.pl
    hr
    if [ "$version" != "2.2" ]; then
        ERRCODE=2 run_grep "CRITICAL: namenode security enabled 'false'" $perl -T ./check_hadoop_namenode_security_enabled.pl
        hr
    fi
    run $perl -T ./check_hadoop_namenode_ha_state.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_namenode_ha_state.pl
    hr
    run $perl -T ./check_hadoop_namenode_ha_state.pl --active
    hr
    run_fail 2 $perl -T ./check_hadoop_namenode_ha_state.pl --standby
    hr
    run $perl -T ./check_hadoop_replication.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_replication.pl
    hr
    # ================================================
    check_newer_plugins
    hr
    check_older_plugins
    hr
    # ================================================
    echo
    echo "Now checking YARN Job plugins, including running the classic MR MonteCarlo Pi job:"
    echo
    run_fail 2 ./check_hadoop_yarn_app_running.py -a '.*'
    hr
    run_conn_refused ./check_hadoop_yarn_app_running.py -a '.*'
    hr
    run_fail 2 ./check_hadoop_yarn_app_running.py -a '.*' -v
    hr
    # ================================================
    run_fail 2 ./check_hadoop_yarn_app_last_run.py -a '.*'
    hr
    run_fail 2 ./check_hadoop_yarn_app_last_run.py -a '.*' -v
    hr
    run_conn_refused ./check_hadoop_yarn_app_last_run.py -a '.*'
    hr
    # ================================================
    run ./check_hadoop_yarn_long_running_apps.py
    hr
    run ./check_hadoop_yarn_long_running_apps.py -v
    hr
    run_conn_refused ./check_hadoop_yarn_long_running_apps.py -v
    hr
    # ================================================
    run_fail 2 ./check_hadoop_yarn_app_running.py -l
    hr
    run_fail 2 ./check_hadoop_yarn_app_last_run.py -l
    hr
    run_fail 3 ./check_hadoop_yarn_queue_apps.py -l
    hr
    run_fail 3 ./check_hadoop_yarn_long_running_apps.py -l
    hr
    # ================================================
    # TODO: add pi job run and kill it to test ./check_hadoop_yarn_app_last_run.py for KILLED status
    # TODO: add teragen job run with bad preexisting output dir to test ./check_hadoop_yarn_app_last_run.py for FAILED status
    # TODO: use --include --exclude to work around the two tests
    echo "Running sample mapreduce job to test Yarn application / job based plugins against:"
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<EOF &
    echo
    echo "running mapreduce job from sample jar"
    echo
    hadoop jar /hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar pi 20 20 &>/dev/null &
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
    if [ $? -ne 0 ]; then
        # Job can get stuck in Accepted state with no NM to run on if disk > 90% full it gets marked as bad dir - Docker images have been updated to permit 100% / not check disk utilization so there is more chance of this working on machines with low disk space left, eg. your laptop
        echo "FAILED: MapReduce job was not detected as running after $max_wait_job_running_secs secs (is disk >90% full?)"
        exit 1
    fi
    set -e
    hr
    echo "Checking app listings while there is an app running:"
    echo
    echo
    run_fail 3 ./check_hadoop_yarn_app_running.py -l
    echo
    echo
    hr
    echo
    echo
    run_fail 3 ./check_hadoop_yarn_queue_apps.py -l
    hr
    echo
    echo
    run_fail 3 ./check_hadoop_yarn_long_running_apps.py -l
    echo
    echo
    hr
    run ./check_hadoop_yarn_app_running.py -a '.*' -v
    hr
    run ./check_hadoop_yarn_app_running.py -a 'monte.*carlo'
    hr
    run_grep "checked 1 out of" ./check_hadoop_yarn_long_running_apps.py --include=montecarlo
    hr
    run ./check_hadoop_yarn_long_running_apps.py
    hr
    run ./check_hadoop_yarn_long_running_spark_shells.py
    hr
    run_fail 2 ./check_hadoop_yarn_long_running_apps.py -c 2
    hr
    run ./check_hadoop_yarn_queue_apps.py
    hr
    run ./check_hadoop_yarn_queue_apps.py --allow monte
    hr
    run_fail 1 ./check_hadoop_yarn_queue_apps.py --disallow monte
    hr
    run_fail 1 ./check_hadoop_yarn_queue_apps.py --allow nonmatching
    hr
    run_grep "checked 1 out of" ./check_hadoop_yarn_long_running_apps.py
    hr
    run_grep "checked 0 out of" ./check_hadoop_yarn_long_running_apps.py --queue nonexistentqueue
    hr
    run_grep "checked 1 out of" ./check_hadoop_yarn_long_running_apps.py --include='te.*carl'
    hr
    run_grep "checked 0 out of" ./check_hadoop_yarn_long_running_apps.py --include=montecarlo --exclude=m.nte
    hr
    run_grep "checked 0 out of" ./check_hadoop_yarn_long_running_apps.py --include=montecarlo --exclude-queue default
    hr
    run_grep "checked 0 out of" ./check_hadoop_yarn_long_running_apps.py --exclude=quasi
    hr
    echo "waiting for job to stop running:"
    ERRCODE=2 RETRY_INTERVAL=2 retry 100 ./check_hadoop_yarn_app_running.py -a 'monte'
    hr
    echo "Checking listing app history:"
    echo
    echo
    run_fail 3 ./check_hadoop_yarn_app_last_run.py -l
    echo "now testing last run status:"
    run ./check_hadoop_yarn_app_last_run.py -a '.*' -v
    hr
    run ./check_hadoop_yarn_app_last_run.py -a montecarlo
    # ================================================
    hr
    run $perl -T ./check_hadoop_yarn_app_stats.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_app_stats.pl
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_app_stats_queue.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_app_stats_queue.pl
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_metrics.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_metrics.pl
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_node_manager.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_node_manager.pl
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_node_managers.pl -w 1 -c 1
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_node_managers.pl -w 1 -c 1
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_node_manager_via_rm.pl --node "$hostname"
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_node_manager_via_rm.pl --node "$hostname"
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_queue_capacity.pl
    hr
    run $perl -T ./check_hadoop_yarn_queue_capacity.pl --queue default
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_queue_capacity.pl
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_queue_state.pl
    hr
    run $perl -T ./check_hadoop_yarn_queue_state.pl --queue default
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_queue_state.pl
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_resource_manager_heap.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_resource_manager_heap.pl
    hr
    # ================================================
    # returns -1 for NonHeapMemoryUsage max
    run_fail 3 $perl -T ./check_hadoop_yarn_resource_manager_heap.pl --non-heap
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_resource_manager_heap.pl --non-heap
    hr
    # ================================================
    run_conn_refused ./check_hadoop_yarn_resource_manager_ha_state.py
    hr
    # ================================================
    run $perl -T ./check_hadoop_yarn_resource_manager_state.pl
    hr
    run_conn_refused $perl -T ./check_hadoop_yarn_resource_manager_state.pl
    hr
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
    ERRCODE=1 retry 30 $perl -T ./check_hadoop_datanodes.pl
    hr
    echo "datanodes should be in warning state at this point due to being stale with contact lag but not yet marked dead:"
    ERRCODE=1 run_grep '1 stale' $perl -T ./check_hadoop_datanodes.pl
    hr
    # typically 10-20 secs since last contact by this point
    run_fail 1 ./check_hadoop_datanode_last_contact.py --node "$hostname" -w 5
    hr
    run_fail 2 ./check_hadoop_datanode_last_contact.py --node "$hostname" -c 5
    hr
    # ================================================
    # TODO: submit job to get stuck in ACCEPTED state and test yarn apps plugins again
    echo "waiting for Yarn Resource Manager to detect NodeManager failure:"
    ERRCODE=1 RETRY_INTERVAL=3 retry 60 $perl -T ./check_hadoop_yarn_node_managers.pl -w 0 -c 1
    hr
    ERRCODE=2 retry 10 $perl -T ./check_hadoop_yarn_node_manager_via_rm.pl --node "$hostname"
    hr
    # ================================================
    # API endpoint not available in Hadoop 2.2
    if [ "$version" != "2.2" ]; then
        # still passes as it's only metadata
        # the check for corrupt / missing blocks / files should catch the fact that the underlying data is offline
        docker_exec check_hadoop_hdfs_file_webhdfs.pl -H localhost -p /tmp/test.txt --owner root --group supergroup --replication 1 --size 8 --last-accessed 600 --last-modified 600 --blockSize 134217728
        hr
        # run inside Docker container so it can resolve redirect to DN
        ERRCODE=2 docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost
        hr
    fi
    run_fail 2 $perl -T ./check_hadoop_yarn_node_manager.pl
    hr
    # ================================================
    run_fail 1 $perl -T ./check_hadoop_yarn_node_managers.pl -w 0 -c 1
    hr
    run_fail 2 $perl -T ./check_hadoop_yarn_node_managers.pl -w 0 -c 0
    hr
    # ================================================
    run_fail 2 $perl -T ./check_hadoop_yarn_node_manager_via_rm.pl --node "$hostname"
    hr
    # ================================================
    hr
    echo "Now waiting on datanode to be marked as dead:"
    # NN 2 * heartbeatRecheckInterval (10) + 10 * 1000 * heartbeatIntervalSeconds == 50 secs
    ERRCODE=2 retry 50 $perl -T ./check_hadoop_datanodes.pl -c 0
    hr
    run_fail 2 $perl -T ./check_hadoop_datanodes.pl -c 0
    hr
    # ================================================
    # stuff from here will must be tested after worker
    # thresholds have been exceeded, relying on latch
    # from retry on datanodes above
    # ================================================
    echo "check datanode last contact returns critical if node is marked as dead regardless of the thresholds:"
    run_fail 2 ./check_hadoop_datanode_last_contact.py --node "$hostname" -w 999999999 -c 9999999999
    hr
    run_fail 2 ./check_hadoop_datanodes_block_balance.py -w 5 -c 10
    hr
    run_fail 2 ./check_hadoop_hdfs_balance.py -w 5 -c 10 -v
    hr
    # space will show 0% but datanodes < 1 should trigger warning
    ERRCODE=1 docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hadoop --hadoop-user root --hdfs-space -w 80 -c 90 -t 20
    hr
    # XXX: doesn't detect missing blocks yet - revisit
    #ERRCODE=2 docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --replication -w 1 -c 1 -t 20
    hr
    ERRCODE=1 docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --balance -w 5 -c 10 -t 20
    hr
    ERRCODE=2 docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --nodes-available -w 1 -c 1 -t 20
    hr
    # API field not available in Hadoop 2.2
    if [ "$version" != "2.2" ]; then
        ERRCODE=2 retry 20 ./check_hadoop_hdfs_corrupt_files.py -v
        hr
        run_fail 2 ./check_hadoop_hdfs_corrupt_files.py -v
        hr
        run_fail 2 ./check_hadoop_hdfs_corrupt_files.py -vv
        hr
        # still passes as it's only metadata
        docker_exec check_hadoop_hdfs_file_webhdfs.pl -H localhost -p /tmp/test.txt --owner root --group supergroup --replication 1 --size 8 --last-accessed 600 --last-modified 600 --blockSize 134217728
        hr
        # run inside Docker container so it can resolve redirect to DN
        ERRCODE=2 docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost
        hr
    fi
    ERRCODE=2 retry 20 $perl -T ./check_hadoop_hdfs_space.pl
    hr
    run_fail 2 $perl -T ./check_hadoop_hdfs_space.pl
    hr
    run_fail 2 ./check_hadoop_hdfs_space.py
    hr
    run_fail 2 $perl -T ./check_hadoop_replication.pl
    hr
    if [[ "$version" =~ ^2\.[0-6]$ ]]; then
        echo
        echo "Now running legacy checks against failure scenarios:"
        echo
        run_fail 3 $perl -T ./check_hadoop_datanodes_block_balance.pl -w 5 -c 10
        hr
        run_fail 3 $perl -T ./check_hadoop_datanodes_blockcounts.pl
        hr
        run_fail 1 $perl -T ./check_hadoop_namenode.pl -v --balance -w 5 -c 10
        hr
        run_fail 2 $perl -T ./check_hadoop_namenode.pl -v --hdfs-space
        hr
        run_fail 2 $perl -T ./check_hadoop_namenode.pl -v --replication -w 10 -c 20
        hr
        run_fail 3 $perl -T ./check_hadoop_namenode.pl -v --datanode-blocks
        hr
        run_fail 3 $perl -T ./check_hadoop_namenode.pl --datanode-block-balance -w 5 -c 20
        hr
        run_fail 3 $perl -T ./check_hadoop_namenode.pl --datanode-block-balance -w 5 -c 20 -v
        hr
        run_fail 1 $perl -T ./check_hadoop_namenode.pl -v --node-count -w 1 -c 0
        hr
        echo "checking node count (expecting critical < 1 nodes)"
        run_fail 2 $perl -t ./check_hadoop_namenode.pl -v --node-count -w 2 -c 1
        hr
        run_fail 2 $perl -T ./check_hadoop_namenode.pl -v --node-list $hostname
        hr
    fi
    hr
    # This takes ages and we aren't going to git commit the collected log from Jenkins or Travis CI
    # so don't bother running on there are it would only time out the builds anyway
    local fsck_log="$data_dir/hdfs-fsck-fail-$version.log"
    if ! is_CI; then
        if [ "$version" != "latest" -a "$version" != ".*" ]; then
            # It's so damn slow to wait for hdfs to convert that let's not do this every time as these tests
            # are already taking too long and having a saved failure case covers it anyway, don't need the dynamic check
            # this takes over 150 secs in tests :-/
            max_fsck_wait_time=1900
            if ! test -s "$fsck_log"; then
                echo "getting new hdfs failure fsck:"
                #docker-compose exec "$DOCKER_SERVICE" /bin/bash <<-EOF
                docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
                    set -euo pipefail
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
                dump_fsck_log "$fsck_log"
                ERRCODE=2 docker_exec check_hadoop_hdfs_fsck.pl -f "/tmp/hdfs-fsck.log" # --last-fsck -w 1 -c 200000000
                hr
            fi
        fi
    fi
    if [ -f "$fsck_log" ]; then
        run_fail 2 $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log"
        hr
        run_fail 2 $perl -T ./check_hadoop_hdfs_fsck.pl -f "$fsck_log" --stats
        hr
    fi
    echo "Completed $run_count Hadoop tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
    echo
}

check_newer_plugins(){
    echo
    echo "Now checking plugins that do not work on older versions of Hadoop:"
    echo
    if [ "$version" != "2.2" ]; then
        # corrupt fields field is not available in older versions of Hadoop
        run ./check_hadoop_hdfs_corrupt_files.py
        hr
        # WebHDFS API endpoint not present in Hadoop 2.2
        # run inside Docker container so it can resolve redirect to DN
        docker_exec check_hadoop_hdfs_file_webhdfs.pl -H localhost -p /tmp/test.txt --owner root --group supergroup --replication 1 --size 8 --last-accessed 600 --last-modified 600 --blockSize 134217728
        hr
        # run inside Docker container so it can resolve redirect to DN
        docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost
        hr
        ERRCODE=2 docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost -P "$wrong_port"
        hr
        # Yarn RM HA state field not available in older versions of Hadoop
        run ./check_hadoop_yarn_resource_manager_ha_state.py
        hr
        run ./check_hadoop_yarn_resource_manager_ha_state.py --active
        hr
        run_fail 2 ./check_hadoop_yarn_resource_manager_ha_state.py --standby
    fi
}

check_older_plugins(){
    echo
    echo "Now checking plugins that do not work on newer versions of Hadoop:"
    echo
    # TODO: write replacement python plugins for this stuff
    # XXX: Hadoop doesn't expose this information in the same way any more via dfshealth.jsp so these plugins are end of life with Hadoop 2.6
    if [[ "$version" =~ ^2\.[0-6]$ ]]; then
        # gets 404 not found on newer Hadoop versions
        run $perl -T ./check_hadoop_datanode_blockcount.pl
        hr
        run_conn_refused $perl -T ./check_hadoop_datanode_blockcount.pl
        hr
        run $perl -T ./check_hadoop_datanodes_block_balance.pl -w 5 -c 10
        hr
        run $perl -T ./check_hadoop_datanodes_block_balance.pl -w 5 -c 10 -v
        hr
        run_conn_refused $perl -T ./check_hadoop_datanodes_block_balance.pl -w 5 -c 10
        hr
        run $perl -T ./check_hadoop_datanodes_blockcounts.pl
        hr
        run_conn_refused $perl -T ./check_hadoop_datanodes_blockcounts.pl
        hr
        # on a real cluster thresholds should be set to millions+, no defaults as must be configured based on NN heap allocated
        # XXX: Total Blocks are not available via blockScannerReport from Hadoop 2.7
        run $perl -T ./check_hadoop_hdfs_total_blocks.pl -w 10 -c 20
        hr
        run_conn_refused $perl -T ./check_hadoop_hdfs_total_blocks.pl -w 10 -c 20
        hr
        echo "testing failure scenarios:"
        run_fail 1 $perl -T ./check_hadoop_hdfs_total_blocks.pl -w 0 -c 4
        hr
        run_fail 2 $perl -T ./check_hadoop_hdfs_total_blocks.pl -w 0 -c 0
        hr
        run_conn_refused $perl -T ./check_hadoop_hdfs_total_blocks.pl -w 0 -c 1
        hr
        run $perl -T ./check_hadoop_namenode.pl -v --balance -w 5 -c 10
        hr
        run $perl -T ./check_hadoop_namenode.pl -v --hdfs-space
        hr
        run $perl -T ./check_hadoop_namenode.pl -v --replication -w 10 -c 20
        hr
        run $perl -T ./check_hadoop_namenode.pl -v --datanode-blocks
        hr
        run $perl -T ./check_hadoop_namenode.pl --datanode-block-balance -w 5 -c 20
        hr
        run $perl -T ./check_hadoop_namenode.pl --datanode-block-balance -w 5 -c 20 -v
        hr
        run $perl -T ./check_hadoop_namenode.pl -v --node-count -w 1 -c 1
        hr
        echo "checking node count (expecting warning < 2 nodes)"
        run_fail 1 $perl -t ./check_hadoop_namenode.pl -v --node-count -w 2 -c 1
        hr
        echo "checking node count (expecting critical < 2 nodes)"
        run_fail 2 $perl -t ./check_hadoop_namenode.pl -v --node-count -w 2 -c 2
        hr
        run $perl -T ./check_hadoop_namenode.pl -v --node-list $hostname
        hr
        run $perl -T ./check_hadoop_namenode.pl -v --heap-usage -w 80 -c 90
        hr
        echo "checking we can trigger warning on heap usage"
        run_fail 1 $perl -T ./check_hadoop_namenode.pl -v --heap-usage -w 1 -c 90
        hr
        echo "checking we can trigger critical on heap usage"
        run_fail 2 $perl -T ./check_hadoop_namenode.pl -v --heap-usage -w 0 -c 1
        hr
        run $perl -T ./check_hadoop_namenode.pl -v --non-heap-usage -w 80 -c 90
        # these won't trigger as NN has no max non-heap
#        echo "checking we can trigger warning on non-heap usage"
#        set +e
#        $perl -T ./check_hadoop_namenode.pl - P"$HADOOP_NAMENODE_PORT" -v --non-heap-usage -w 1 -c 90
#        check_exit_code 1
#        hr
#        echo "checking we can trigger critical on non-heap usage"
#        set +e
#        $perl -T ./check_hadoop_namenode.pl -P "$HADOOP_NAMENODE_PORT" -v --non-heap-usage -w 0 -c 1
#        check_exit_code 2
#        set -e
#        hr
    fi
}

run_test_versions Hadoop
