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

srcdir="$srcdir2/.."

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
export HADOOP_PORTS="8042 8088 9000 10020 19888 50010 50020 50070 50075 50090"

export DOCKER_IMAGE="harisekhon/hadoop-dev"
export DOCKER_CONTAINER="nagios-plugins-hadoop-test"

export MNTDIR="/pl"

startupwait 30

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Hadoop checks!!!'
    exit 0
fi

docker_exec(){
    docker exec -ti "$DOCKER_CONTAINER" $MNTDIR/$@
}

test_hadoop(){
    local version="$1"
    hr
    echo "Setting up Hadoop $version test container"
    hr
    DOCKER_OPTS="-v $srcdir2/..:$MNTDIR"
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $HADOOP_PORTS
    when_ports_available $startupwait $HADOOP_HOST $HADOOP_PORTS
    echo "creating test file in hdfs"
    docker exec -i "$DOCKER_CONTAINER" /bin/bash <<-EOF
        export JAVA_HOME=/usr
        hdfs dfsadmin -safemode leave
        hdfs dfs -rm -f /tmp/test.txt &>/dev/null
        echo content | hdfs dfs -put - /tmp/test.txt
        hdfs fsck / &> /tmp/hdfs-fsck.log.tmp && tail -n30 /tmp/hdfs-fsck.log.tmp > /tmp/hdfs-fsck.log
EOF
    echo
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    hr
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    $perl -T ./check_hadoop_yarn_resource_manager_version.pl -v -e "$version"
    $perl -T ./check_hadoop_hdfs_datanode_version.pl -N $(docker exec "$DOCKER_CONTAINER" hostname) -v -e "$version"
    hr
    docker_exec check_hadoop_balance.pl -w 5 -c 10 --hadoop-bin /hadoop/bin/hdfs --hadoop-user root -t 60
    hr
    $perl -T ./check_hadoop_checkpoint.pl
    hr
    # XXX: requires updates for 2.7
    #$perl -T ./check_hadoop_datanode_blockcount.pl -H $HADOOP_HOST
    hr
    $perl -T ./check_hadoop_datanode_jmx.pl --all-metrics
    hr
    # XXX: requires updates for 2.7
    #$perl -T ./check_hadoop_datanodes_block_balance.pl -H $HADOOP_HOST -w 5 -c 10 -vvv
    #$perl -T ./check_hadoop_datanodes_blockcounts.pl -H $HADOOP_HOST -vvv
    hr
    $perl -T ./check_hadoop_datanodes.pl
    hr
    # would be much higher on a real cluster, no defaults as much be configured based on NN heap
    # XXX: 404
    #$perl -T ./check_hadoop_hdfs_blocks.pl -w 100 -c 200
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
    #docker_exec check_hadoop_hdfs_space.pl -H localhost -vvv
    hr
    # run inside Docker container so it can resolve redirect to DN
    docker_exec check_hadoop_hdfs_write_webhdfs.pl -H localhost
    hr
    $perl -T ./check_hadoop_jmx.pl -P 8042 -a
    hr
    $perl -T ./check_hadoop_jmx.pl -P 8088 -a
    hr
    $perl -T ./check_hadoop_jmx.pl -P 50070 -a
    hr
    $perl -T ./check_hadoop_jmx.pl -P 50075 -a
    hr
    $perl -T ./check_hadoop_namenode_heap.pl
    hr
    # XXX: fix required for non-integer? Happens just after booting Hadoop docker image
    #$perl -T ./check_hadoop_namenode_heap.pl --non-heap -vvv
    hr
    $perl -T ./check_hadoop_namenode_jmx.pl --all-metrics
    hr
    # all the hadoop namenode checks need updating
    # 404 not found
    #$perl -T ./check_hadoop_namenode.pl -b -w 5 -c 10
    hr
    $perl -T ./check_hadoop_namenode_safemode.pl
    hr
    set +o pipefail
    $perl -T ./check_hadoop_namenode_security_enabled.pl | grep -Fx "CRITICAL: namenode security enabled 'false'"
    set -o pipefail
    hr
    $perl -T ./check_hadoop_namenode_state.pl
    hr
    $perl -T ./check_hadoop_replication.pl
    hr
    $perl -T ./check_hadoop_yarn_app_stats.pl
    hr
    $perl -T ./check_hadoop_yarn_app_stats_queue.pl
    hr
    $perl -T ./check_hadoop_yarn_metrics.pl
    hr
    $perl -T ./check_hadoop_yarn_node_manager.pl
    hr
    $perl -T ./check_hadoop_yarn_node_managers.pl -w 1 -c 1
    hr
    $perl -T ./check_hadoop_yarn_node_manager_via_rm.pl --node $(docker ps | awk "/$DOCKER_CONTAINER/{print \$1}")
    hr
    $perl -T ./check_hadoop_yarn_queue_capacity.pl
    $perl -T ./check_hadoop_yarn_queue_capacity.pl --queue default
    hr
    $perl -T ./check_hadoop_yarn_queue_state.pl
    $perl -T ./check_hadoop_yarn_queue_state.pl --queue default
    hr
    $perl -T ./check_hadoop_yarn_resource_manager_heap.pl
    # non integer NonHeapMemoryUsage
    #$perl -T ./check_hadoop_yarn_resource_manager_heap.pl --non-heap
    hr
    $perl -T ./check_hadoop_yarn_resource_manager_state.pl
    hr
    delete_container
}

for version in $(ci_sample $HADOOP_VERSIONS); do
    test_hadoop $version
done
