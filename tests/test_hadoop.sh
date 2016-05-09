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

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

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

hr
echo "Setting up Hadoop test container"
hr
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" 8032 8088 9000 10020 19888 50010 50020 50070 50075 50090

hr
# TODO: add checks
#$perl -T $I_lib 
#hr
#$perl -T $I_lib 
hr
if is_zookeeper_built; then
    $perl -T $I_lib 
else
    echo "ZooKeeper not built - skipping ZooKeeper checks"
fi
hr
delete_container
