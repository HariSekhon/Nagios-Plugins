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

export HADOOP_VERSIONS="${@:-${HADOOP_VERSIONS:-latest 2.5 2.6 2.7}}"

HADOOP_HOST="${DOCKER_HOST:-${HADOOP_HOST:-${HOST:-localhost}}}"
HADOOP_HOST="${HADOOP_HOST##*/}"
HADOOP_HOST="${HADOOP_HOST%%:*}"
export HADOOP_HOST
export HADOOP_NAMENODE_PORT="50070"
export HADOOP_DATANODE_PORT="50075"
export HADOOP_YARN_RESOURCE_MANAGER_PORT="8088"
export HADOOP_YARN_NODE_MANAGER_PORT="8042"
export HADOOP_PORTS="8042 8088 50010 50020 50070 50075 50090"

export DOCKER_IMAGE="harisekhon/hadoop-dev"

export MNTDIR="/pl"

startupwait 30

check_docker_available

docker_exec(){
    #docker-compose exec "$DOCKER_SERVICE" $MNTDIR/$@
    docker exec "nagiosplugins_${DOCKER_SERVICE}_1" $MNTDIR/$@
}

test_hadoop(){
    local version="$1"
    section2 "Setting up Hadoop $version test container"
    #DOCKER_OPTS="-v $srcdir2/..:$MNTDIR"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $HADOOP_PORTS
    VERSION="$version" docker-compose up -d
    echo "getting Hadoop dynamic port mappings"
    printf "getting HDFS NN port => "
    local hadoop_namenode_port="`docker-compose port "$DOCKER_SERVICE" "$HADOOP_NAMENODE_PORT" | sed 's/.*://'`"
    echo "$hadoop_namenode_port"
    printf "getting HDFS DN port => "
    local hadoop_datanode_port="`docker-compose port "$DOCKER_SERVICE" "$HADOOP_DATANODE_PORT" | sed 's/.*://'`"
    echo "$hadoop_datanode_port"
    printf  "getting Yarn RM port => "
    local hadoop_yarn_resource_manager_port="`docker-compose port "$DOCKER_SERVICE" "$HADOOP_YARN_RESOURCE_MANAGER_PORT" | sed 's/.*://'`"
    echo "$hadoop_yarn_resource_manager_port"
    printf "getting Yarn NM port => "
    local hadoop_yarn_node_manager_port="`docker-compose port "$DOCKER_SERVICE" "$HADOOP_YARN_NODE_MANAGER_PORT" | sed 's/.*://'`"
    echo "$hadoop_yarn_node_manager_port"
    #local hadoop_ports=`{ for x in $HADOOP_PORTS; do docker-compose port "$DOCKER_SERVICE" "$x"; done; } | sed 's/.*://'`
    local hadoop_ports="$hadoop_namenode_port $hadoop_datanode_port $hadoop_yarn_resource_manager_port $hadoop_yarn_node_manager_port"
    when_ports_available "$startupwait" "$HADOOP_HOST" $hadoop_ports
    echo "setting up HDFS for tests"
    #docker-compose exec "$DOCKER_SERVICE" /bin/bash <<-EOF
    docker exec -i "nagiosplugins_${DOCKER_SERVICE}_1" /bin/bash <<-EOF
        export JAVA_HOME=/usr
        echo "leaving safe mode"
        hdfs dfsadmin -safemode leave
        echo "removing old hdfs file /tmp/test.txt if present"
        hdfs dfs -rm -f /tmp/test.txt &>/dev/null
        echo "creating test hdfs file /tmp/test.txt"
        echo content | hdfs dfs -put - /tmp/test.txt
        echo "dumping fsck log"
        hdfs fsck / &> /tmp/hdfs-fsck.log.tmp && tail -n30 /tmp/hdfs-fsck.log.tmp > /tmp/hdfs-fsck.log
        exit
EOF
    echo
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    #echo "waiting 10 secs for Yarn RM to come up to test version"
    #sleep 10
    local count=0
    local max_tries=20
    while true; do
        echo "waiting for Yarn RM cluster page to come up to test version..."
        # intentionally being a bit loose here, if content has changed I would rather it be flagged as up and the plugin fail to parse which is more a more accurate error
        if curl -s "$HADOOP_HOST:$hadoop_yarn_resource_manager_port/ws/v1/cluster" | grep -qi hadoop; then
            break
        fi
        let count+=1
        if [ $count -ge 20 ]; then
            echo "giving up after $max_tries tries"
            break
        fi
        sleep 1
    done
    $perl -T ./check_hadoop_yarn_resource_manager_version.pl -P "$hadoop_yarn_resource_manager_port" -v -e "$version"
    hr
    # docker-compose exec returns $'hostname\r' but not in shell
    hostname="$(docker-compose exec "$DOCKER_SERVICE" hostname | tr -d '$\r')"
    if [ -z "$hostname" ]; then
        echo 'Failed to determine hostname of container via docker-compose exec, cannot continue with tests!'
        exit 1
    fi
    $perl -T ./check_hadoop_hdfs_datanode_version.pl -P "$hadoop_namenode_port" -N "$hostname" -v -e "$version"
    hr
    docker_exec check_hadoop_balance.pl -w 5 -c 10 --hadoop-bin /hadoop/bin/hdfs --hadoop-user root -t 60
    hr
    $perl -T ./check_hadoop_checkpoint.pl -P "$hadoop_namenode_port"
    hr
    # TODO: write replacement python plugin for this
    # XXX: Total Blocks are not available via blockScannerReport from Hadoop 2.7
    if [ "$version" = "2.5" -o "$version" = "2.6" ]; then
        $perl -T ./check_hadoop_datanode_blockcount.pl -H $HADOOP_HOST -P "$hadoop_datanode_port"
    fi
    hr
    $perl -T ./check_hadoop_datanode_jmx.pl -P "$hadoop_datanode_port" --all-metrics
    hr
    # TODO: write replacement python plugins for this
    # XXX: Hadoop doesn't expose this information in the same way any more via dfshealth.jsp so these plugins are end of life with Hadoop 2.6
    if [ "$version" = "2.5" -o "$version" = "2.6" ]; then
        $perl -T ./check_hadoop_datanodes_block_balance.pl -H $HADOOP_HOST -P "$hadoop_namenode_port" -w 5 -c 10
        hr
        $perl -T ./check_hadoop_datanodes_blockcounts.pl -H $HADOOP_HOST -P "$hadoop_namenode_port"
        hr
    fi
    $perl -T ./check_hadoop_datanodes.pl -P "$hadoop_namenode_port"
    hr
    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hadoop --hadoop-user root --hdfs-space -w 80 -c 90
    hr
    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --replication -w 1 -c 1
    hr
    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --balance -w 5 -c 10
    hr
    docker_exec check_hadoop_dfs.pl --hadoop-bin /hadoop/bin/hdfs --hadoop-user root --nodes-available -w 1 -c 1
    hr
    # TODO: write replacement python plugin for this
    # XXX: Hadoop doesn't expose this information in the same way any more via dfshealth.jsp so this plugin is end of life with Hadoop 2.6
    if [ "$version" = "2.5" -o "$version" = "2.6" ]; then
        # would be much higher on a real cluster, no defaults as must be configured based on NN heap
        $perl -T ./check_hadoop_hdfs_blocks.pl -P "$hadoop_namenode_port" -w 100 -c 200
        hr
    fi
    hr
    # run inside Docker container so it can resolve redirect to DN
    docker_exec check_hadoop_hdfs_file_webhdfs.pl -H localhost -p /tmp/test.txt --owner root --group supergroup --replication 1 --size 8 --last-accessed 600 --last-modified 600 --blockSize 134217728
    hr
    for x in 2.5 2.6 2.7; do
        ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck-$x.log
        hr
        ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck-$x.log --stats
        hr
    done
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log
    hr
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --stats
    hr
    echo "checking hdfs fsck failure scenarios:"
    set +e
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --last-fsck -w 1 -c 200000000
    check_exit_code 1
    hr
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --last-fsck -w 1 -c 1
    check_exit_code 2
    hr
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 1 -c 2
    hr
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 0 -c 1
    check_exit_code 1
    hr
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --max-blocks -w 0 -c 0
    check_exit_code 2
    set -e
    hr
    ./check_hadoop_hdfs_space.pl -H localhost -P "$hadoop_namenode_port"
    hr
    # run inside Docker container so it can resolve redirect to DN
    docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost
    hr
    $perl -T ./check_hadoop_jmx.pl -P "$hadoop_yarn_node_manager_port" -a
    hr
    $perl -T ./check_hadoop_jmx.pl -P "$hadoop_yarn_resource_manager_port" -a
    hr
    $perl -T ./check_hadoop_jmx.pl -P "$hadoop_namenode_port" -a
    hr
    $perl -T ./check_hadoop_jmx.pl -P "$hadoop_datanode_port" -a
    hr
    $perl -T ./check_hadoop_namenode_heap.pl -P "$hadoop_namenode_port"
    hr
    $perl -T ./check_hadoop_namenode_heap.pl -P "$hadoop_namenode_port" --non-heap
    hr
    $perl -T ./check_hadoop_namenode_jmx.pl -P "$hadoop_namenode_port" --all-metrics
    hr
    # TODO: write replacement python plugins for this
    # XXX: Hadoop doesn't expose this information in the same way any more via dfshealth.jsp so this plugin is end of life with Hadoop 2.6
    # gets 404 not found
    if [ "$version" = "2.5" -o "$version" = "2.6" ]; then
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --balance -w 5 -c 10
        hr
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --hdfs-space
        hr
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --replication -w 10 -c 20
        hr
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --datanode-blocks
        hr
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --datanode-block-balance -w 5 -c 20
        hr
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --node-count -w 1 -c 1
        hr
        echo "checking node count (expecting warning < 2 nodes)"
        set +e
        $perl -t ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --node-count -w 2 -c 1
        check_exit_code 1
        hr
        echo "checking node count (expecting critical < 2 nodes)"
        $perl -t ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --node-count -w 2 -c 2
        check_exit_code 2
        set -e
        hr
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --node-list $hostname
        hr
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --heap-usage -w 80 -c 90
        hr
        echo "checking we can trigger warning on heap usage"
        set +e
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --heap-usage -w 1 -c 90
        check_exit_code 1
        hr
        echo "checking we can trigger critical on heap usage"
        set +e
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --heap-usage -w 0 -c 1
        check_exit_code 2
        set -e
        hr
        $perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -v --non-heap-usage -w 80 -c 90
        hr
        # these won't trigger as NN has no max non-heap
#        echo "checking we can trigger warning on non-heap usage"
#        set +e
#        $perl -T ./check_hadoop_namenode.pl -P"$hadoop_namenode_port" -v --non-heap-usage -w 1 -c 90
#        check_exit_code 1
#        hr
#        echo "checking we can trigger critical on non-heap usage"
#        set +e
#        $perl -T ./check_hadoop_namenode.pl -P"$hadoop_namenode_port" -v --non-heap-usage -w 0 -c 1
#        check_exit_code 2
#        set -e
#        hr
    fi
    $perl -T ./check_hadoop_namenode_safemode.pl -P "$hadoop_namenode_port"
    hr
    set +o pipefail
    $perl -T ./check_hadoop_namenode_security_enabled.pl -P "$hadoop_namenode_port" | grep -Fx "CRITICAL: namenode security enabled 'false'"
    set -o pipefail
    hr
    $perl -T ./check_hadoop_namenode_state.pl -P "$hadoop_namenode_port"
    hr
    $perl -T ./check_hadoop_replication.pl -P "$hadoop_namenode_port"
    hr
    $perl -T ./check_hadoop_yarn_app_stats.pl -P "$hadoop_yarn_resource_manager_port"
    hr
    $perl -T ./check_hadoop_yarn_app_stats_queue.pl -P "$hadoop_yarn_resource_manager_port"
    hr
    $perl -T ./check_hadoop_yarn_metrics.pl -P "$hadoop_yarn_resource_manager_port"
    hr
    $perl -T ./check_hadoop_yarn_node_manager.pl -P "$hadoop_yarn_node_manager_port"
    hr
    $perl -T ./check_hadoop_yarn_node_managers.pl -P "$hadoop_yarn_resource_manager_port" -w 1 -c 1
    hr
    $perl -T ./check_hadoop_yarn_node_manager_via_rm.pl -P "$hadoop_yarn_resource_manager_port" --node "$hostname"
    hr
    $perl -T ./check_hadoop_yarn_queue_capacity.pl -P "$hadoop_yarn_resource_manager_port"
    hr
    $perl -T ./check_hadoop_yarn_queue_capacity.pl -P "$hadoop_yarn_resource_manager_port" --queue default
    hr
    $perl -T ./check_hadoop_yarn_queue_state.pl -P "$hadoop_yarn_resource_manager_port"
    hr
    $perl -T ./check_hadoop_yarn_queue_state.pl -P "$hadoop_yarn_resource_manager_port" --queue default
    hr
    $perl -T ./check_hadoop_yarn_resource_manager_heap.pl -P "$hadoop_yarn_resource_manager_port"
    # returns -1 for NonHeapMemoryUsage max
    set +e
    $perl -T ./check_hadoop_yarn_resource_manager_heap.pl -P "$hadoop_yarn_resource_manager_port" --non-heap
    check_exit_code 3
    set -e
    hr
    $perl -T ./check_hadoop_yarn_resource_manager_state.pl -P "$hadoop_yarn_resource_manager_port"
    hr
    #delete_container
    docker-compose down
    echo
    echo
}

for version in $(ci_sample $HADOOP_VERSIONS); do
    test_hadoop $version
done
