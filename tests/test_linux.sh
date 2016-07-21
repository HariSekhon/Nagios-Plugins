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

echo "
# ============================================================================ #
#                                   L i n u x
# ============================================================================ #
"

export DOCKER_IMAGE="harisekhon/nagios-plugins"
export DOCKER_CONTAINER="nagios-plugins-linux-test"

export MNTDIR="/tmp/nagios-plugins"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Linux checks!!!'
    exit 0
fi

docker_exec(){
    local cmd="$@"
    docker exec "$DOCKER_CONTAINER" $MNTDIR/$*
}

#trap "docker rm -f $DOCKER_CONTAINER &>/dev/null" SIGINT SIGTERM EXIT

startupwait=0

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Linux checks!!!'
    exit 0
fi

echo "Setting up Linux test container"
DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
DOCKER_CMD="tail -f /dev/null"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER"
docker exec "$DOCKER_CONTAINER" yum makecache fast
docker exec "$DOCKER_CONTAINER" yum install -y net-tools
if [ -n "${ENTER:-}" ]; then
    docker exec -ti "$DOCKER_CONTAINER" bash -c "cd $MNTDIR; exec bash"
fi
if [ -n "${NOTESTS:-}" ]; then
    exit 0
fi
hr
docker_exec check_disk_write.pl -d .
hr
docker_exec check_git_branch_checkout.pl -d "$MNTDIR" -b "$(git branch | awk '/^*/{print $2}')"
hr
echo "Testing failure detection of wrong git branch"
set +e
docker_exec check_git_branch_checkout.pl -d "$MNTDIR" -b nonexistentbranch
[ $? -eq 2 ] || exit 1
set -e
hr
docker_exec check_linux_auth.pl -u root -g root -v
hr
docker_exec check_linux_context_switches.pl || : ; sleep 1; docker_exec check_linux_context_switches.pl -w 10000 -c 50000
hr
docker_exec check_linux_duplicate_IDs.pl
hr
#docker_exec check_linux_interface.pl -i eth0 -v -e -d Full
hr
# making this much higher so it doesn't trip just due to test system load
docker_exec check_linux_load_normalized.pl -w 99 -c 99
hr
docker_exec check_linux_load_normalized.pl -w 99 -c 99 --cpu-cores-perfdata
hr
docker_exec check_linux_ram.py -v -w 20% -c 10%
hr
docker_exec check_linux_system_file_descriptors.pl
hr
docker_exec check_linux_timezone.pl -T UTC -Z /usr/share/zoneinfo/UTC -A UTC -v
hr
docker_exec check_yum.pl -C -v -t 30
hr
docker_exec check_yum.pl -C --all-updates -v -t 30 || :
hr
docker_exec check_yum.py -C -v -t 30
hr
docker_exec check_yum.py -C --all-updates -v -t 30 || :
hr
delete_container

# ============================================================================ #
#                                     E N D
# ============================================================================ #
# old local checks don't run on Mac
exit 0

$perl -T ./check_linux_timezone.pl -T UTC -Z /usr/share/zoneinfo/UTC -A UTC
hr
if [ -x /usr/bin/yum ]; then
    $perl -T ./check_yum.pl
    $perl -T ./check_yum.pl --all-updates || :
    hr
    ./check_yum.py
    ./check_yum.py --all-updates || :
    hr
fi

echo; echo
