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

set -eu
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

export DOCKER_CONTAINER="nagios-plugins"

export MNTDIR="/tmp/nagios-plugins"

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Linux checks!!!'
    exit 0
fi

docker_run_test(){
    local cmd="$@"
    docker exec "$DOCKER_CONTAINER" $MNTDIR/$*
}

#trap "docker rm -f $DOCKER_CONTAINER &>/dev/null" SIGINT SIGTERM EXIT

#startupwait=10
#is_travis && let startupwait+=20

echo "Setting up Linux test container"
if ! is_docker_container_running "$DOCKER_CONTAINER"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Linux test container"
    docker run -d --name "$DOCKER_CONTAINER" -v "$srcdir/..":"$MNTDIR" harisekhon/nagios-plugins tail -f /dev/null
    docker exec "$DOCKER_CONTAINER" yum makecache fast
    docker exec "$DOCKER_CONTAINER" yum install -y net-tools
else
        echo "Docker Linux test container already running"
fi

hr
docker_run_test check_linux_auth.pl -u root -g root -v
hr
docker_run_test check_linux_context_switches.pl || : ; sleep 1; docker_run_test check_linux_context_switches.pl -w 10000 -c 50000
hr
docker_run_test check_linux_duplicate_IDs.pl
hr
#docker_run_test check_linux_interface.pl -i eth0 -v -e -d Full
hr
# making this much higher so it doesn't trip just due to test system load
docker_run_test check_linux_load_normalized.pl -w 99 -c 99
hr
docker_run_test check_linux_ram.py -v -w 20% -c 10%
hr
docker_run_test check_linux_system_file_descriptors.pl
hr
docker_run_test check_linux_timezone.pl -T UTC -Z /usr/share/zoneinfo/UTC -A UTC -v
hr
docker_run_test check_yum.pl -C -v -t 30
hr
docker_run_test check_yum.pl -C --all-updates -v -t 30 || :
hr
docker_run_test check_yum.py -C -v -t 30
hr
docker_run_test check_yum.py -C --all-updates -v -t 30 || :
hr
echo
if [ -z "${NODELETE:-}" ]; then
    echo -n "Deleting container "
    docker rm -f "$DOCKER_CONTAINER"
fi
echo; echo

# ============================================================================ #
#                                     E N D
# ============================================================================ #
# old local checks don't run on Mac
exit 0

$perl -T $I_lib ./check_linux_timezone.pl -T UTC -Z /usr/share/zoneinfo/UTC -A UTC
hr
if [ -x /usr/bin/yum ]; then
    $perl -T $I_lib ./check_yum.pl
    $perl -T $I_lib ./check_yum.pl --all-updates || :
    hr
    ./check_yum.py
    ./check_yum.py --all-updates || :
    hr
fi

echo; echo
