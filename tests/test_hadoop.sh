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

echo "
# ============================================================================ #
#                                  H a d o o p
# ============================================================================ #
"

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

startupwait 80

check_docker_available

docker_exec(){
    docker-compose exec "$DOCKER_SERVICE" $MNTDIR/$@
}

test_hadoop(){
    local version="$1"
    hr
    echo "Setting up Hadoop $version test container"
    hr
    #DOCKER_OPTS="-v $srcdir2/..:$MNTDIR"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $HADOOP_PORTS
    VERSION="$version" docker-compose up -d
    hadoop_namenode_port="`docker-compose port "$DOCKER_SERVICE" "$HADOOP_NAMENODE_PORT" | sed 's/.*://'`"
    hadoop_datanode_port="`docker-compose port "$DOCKER_SERVICE" "$HADOOP_DATANODE_PORT" | sed 's/.*://'`"
    hadoop_yarn_resource_manager_port="`docker-compose port "$DOCKER_SERVICE" "$HADOOP_YARN_RESOURCE_MANAGER_PORT" | sed 's/.*://'`"
    hadoop_yarn_node_manager_port="`docker-compose port "$DOCKER_SERVICE" "$HADOOP_YARN_NODE_MANAGER_PORT" | sed 's/.*://'`"
    hadoop_ports=`{ for x in $HADOOP_PORTS; do docker-compose port "$DOCKER_SERVICE" "$x"; done; } | sed 's/.*://'`
    when_ports_available "$startupwait" "$HADOOP_HOST" $hadoop_ports
    echo "creating test file in hdfs"
    docker-compose exec "$DOCKER_SERVICE" /bin/bash <<-EOF
        export JAVA_HOME=/usr
        hdfs dfsadmin -safemode leave
        hdfs dfs -rm -f /tmp/test.txt &>/dev/null
        echo content | hdfs dfs -put - /tmp/test.txt
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
    # XXX: requires updates for 2.7
    #$perl -T ./check_hadoop_datanode_blockcount.pl -H $HADOOP_HOST -P "$hadoop_datanode_port"
    hr
    $perl -T ./check_hadoop_datanode_jmx.pl -P "$hadoop_datanode_port" --all-metrics
    hr
    # XXX: requires updates for 2.7
    #$perl -T ./check_hadoop_datanodes_block_balance.pl -H $HADOOP_HOST -P "$hadoop_namenode_port" -w 5 -c 10 -vvv
    #$perl -T ./check_hadoop_datanodes_blockcounts.pl -H $HADOOP_HOST -P "$hadoop_namenode_port" -vvv
    hr
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
    # would be much higher on a real cluster, no defaults as must be configured based on NN heap
    # XXX: 404
    #$perl -T ./check_hadoop_hdfs_blocks.pl -P "$hadoop_namenode_port" -w 100 -c 200
    hr
    # run inside Docker container so it can resolve redirect to DN
    docker_exec check_hadoop_hdfs_file_webhdfs.pl -H localhost -p /tmp/test.txt --owner root --group supergroup --replication 1 --size 8 --last-accessed 600 --last-modified 600 --blockSize 134217728
    hr
    ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck.log
    hr
    ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck.log --stats
    set +e
    ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck.log --last-fsck -w 10 -c 200000000
    check_exit_code 1
    set -e
    hr
    set +e
    ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck.log --last-fsck -w 10 -c 20
    check_exit_code 2
    set -e
    hr
    ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck.log --max-blocks -w 1 -c 2
    hr
    set +e
    ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck.log --max-blocks -w 0 -c 1
    check_exit_code 1
    set -e
    hr
    set +e
    ./check_hadoop_hdfs_fsck.pl -f tests/data/hdfs-fsck.log --max-blocks -w 0 -c 0
    check_exit_code 2
    set -e
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log
    hr
    docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log --stats
    hr
    # XXX: fix required for very small E number
    #docker_exec check_hadoop_hdfs_space.pl -H localhost -P "$hadoop_namenode_port" -vvv
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
    # XXX: fix required for non-integer? Happens just after booting Hadoop docker image
    #$perl -T ./check_hadoop_namenode_heap.pl --non-heap -vvv
    hr
    $perl -T ./check_hadoop_namenode_jmx.pl -P "$hadoop_namenode_port" --all-metrics
    hr
    # all the hadoop namenode checks need updating
    # 404 not found
    #$perl -T ./check_hadoop_namenode.pl -P "$hadoop_namenode_port" -b -w 5 -c 10
    hr
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
    $perl -T ./check_hadoop_yarn_queue_capacity.pl -P "$hadoop_yarn_resource_manager_port" --queue default
    hr
    $perl -T ./check_hadoop_yarn_queue_state.pl -P "$hadoop_yarn_resource_manager_port"
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
}

for version in $(ci_sample $HADOOP_VERSIONS); do
    test_hadoop $version
done
