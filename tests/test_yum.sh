#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-07 13:41:58 +0100 (Wed, 07 Oct 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

#[ `uname -s` = "Linux" ] || exit 0

if [ -z "${FORCE_YUM_CHECKS:-}" ]; then
    # XXX: NO LONGER USED, DONE AS PART OF LINUX CHECKS NOW
    return 0 &>/dev/null || :
    exit 0
fi

section "Y u m"

export DOCKER_IMAGE="harisekhon/centos-github"
export DOCKER_CONTAINER="nagios-plugins-centos-test"

export MNTDIR="/tmp/nagios-plugins"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping CentOS Yum checks!!!'
    exit 0
fi

startupwait 0

echo "Setting up CentOS test container"
DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
DOCKER_CMD="tail -f /dev/null"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER"
docker exec "$DOCKER_CONTAINER" yum makecache fast
#docker exec "$DOCKER_CONTAINER" yum install -y net-tools
if [ -n "${NOTESTS:-}" ]; then
    exit 0
fi
hr
docker_exec check_yum.pl -C -v -t 60
hr
set +e
docker_exec check_yum.pl -C --all-updates -v -t 60
result=$?
set -e
if [ $result -ne 0 -a $result -ne 2 ]; then
    exit 1
fi
hr
docker_exec check_yum.py -C -v -t 60
hr
set +e
docker_exec check_yum.py -C --all-updates -v -t 60
result=$?
set -e
if [ $result -ne 0 -a $result -ne 2 ]; then
    exit 1
fi
hr
echo "Completed $run_count Yum tests"
hr
[ -n "${KEEPDOCKER:-}" ] ||
delete_container
echo; echo
