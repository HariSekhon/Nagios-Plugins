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

HADOOP_HOST="${DOCKER_HOST:-${HADOOP_HOST:-${HOST:-localhost}}}"
HADOOP_HOST="${HADOOP_HOST##*/}"
HADOOP_HOST="${HADOOP_HOST%%:*}"
export HADOOP_HOST
echo "using docker address '$HADOOP_HOST'"

export DOCKER_IMAGE="harisekhon/hadoop-dev"
export DOCKER_CONTAINER="nagios-plugins-hadoop-test"

startupwait=30

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Hadoop checks!!!'
    exit 0
fi

docker_exec(){
    docker exec -ti "$DOCKER_CONTAINER" $MNTDIR/$@
}

hr
echo "Setting up Hadoop test container"
hr
DOCKER_OPTS="-v $srcdir2/..:/pl"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" 8032 8088 9000 10020 19888 50010 50020 50070 50075 50090

echo "creating test file in hdfs"
docker exec -i "$DOCKER_CONTAINER" /bin/bash <<EOF
export JAVA_HOME=/usr
hdfs dfsadmin -safemode leave
echo content | hdfs dfs -put - /tmp/test.txt
hdfs fsck / &> /tmp/hdfs-fsck.log.tmp && tail -n30 /tmp/hdfs-fsck.log.tmp > /tmp/hdfs-fsck.log
EOF

hr
docker_exec check_hadoop_balance.pl -w 5 -c 10 --hadoop-bin /hadoop/bin/hdfs --hadoop-user root
hr
$perl -T $I_lib ./check_hadoop_checkpoint.pl
hr
# XXX: requires updates for 2.7
#$perl -T $I_lib ./check_hadoop_datanode_blockcount.pl -H $HADOOP_HOST
hr
$perl -T $I_lib ./check_hadoop_datanode_jmx.pl --all-metrics
hr
# XXX: requires updates for 2.7
#$perl -T $I_lib ./check_hadoop_datanodes_block_balance.pl -H $HADOOP_HOST -w 5 -c 10 -vvv
#$perl -T $I_lib ./check_hadoop_datanodes_blockcounts.pl -H $HADOOP_HOST -vvv
hr
$perl -T $I_lib ./check_hadoop_datanodes.pl
hr
# would be much higher on a real cluster, no defaults as much be configured based on NN heap
$perl -T $I_lib ./check_hadoop_hdfs_blocks.pl -w 100 -c 200
hr
# XXX: fix required
$perl -T $I_lib ./check_hadoop_hdfs_file_webhdfs.pl -p /tmp/test.txt --owner root --group root --replication 1 --size 10 --last-accessed 600 --last-modified 600 --blockSize 134217728
hr
# XXX: fix required
#docker_exec check_hadoop_hdfs_fsck.pl -f /tmp/hdfs-fsck.log -vvv
# XXX: fix required for very small E number
#docker_exec check_hadoop_hdfs_space.pl -H localhost -vvv
hr
$perl -T $I_lib ./check_hadoop_hdfs_write_webhdfs.pl
hr
$perl -T $I_lib ./check_hadoop_jmx.pl -H localhost -P 8088 -a
hr
$perl -T $I_lib ./check_hadoop_jmx.pl -H localhost -P 50070 -a
hr
$perl -T $I_lib ./check_hadoop_jmx.pl -H localhost -P 50075 -a
hr
if is_zookeeper_built; then
    #$perl -T $I_lib 
    :
else
    echo "ZooKeeper not built - skipping ZooKeeper checks"
fi
hr
delete_container
