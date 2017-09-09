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

check_docker_available

export MNTDIR="/pl"

docker_exec(){
    echo "docker-compose exec '$SERVICE' $MNTDIR/$*"
    docker-compose exec "$SERVICE" $MNTDIR/$*
}

# TODO: build specific versions to test for CentOS 6 + 7, Ubuntu 14.04 + 16.04, Debian Wheezy + Jessie, Alpine builds
test_linux(){
    local distro="$1"
    local version="$2"
    echo "Setting up Linux $distro $version test container"
    #DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
    #DOCKER_CMD="tail -f /dev/null"
    #launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER"
    export SERVICE="$distro-github"
    export COMPOSE_FILE="$srcdir/docker/$distro-github-docker-compose.yml"
    VERSION="$version" docker-compose up -d
    #docker exec "$DOCKER_CONTAINER" yum install -y net-tools
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    docker_exec check_disk_write.pl -d .
    hr
    hr
    docker_exec check_linux_auth.pl -u root -g root -v
    hr
    docker_exec check_linux_context_switches.pl || : ; sleep 1; docker_exec check_linux_context_switches.pl -w 10000 -c 50000
    hr
    docker_exec check_linux_duplicate_IDs.pl
    hr
    # temporary fix until slow DockerHub automated builds trickle through ethtool in docker images
    docker-compose exec "$SERVICE" sh <<EOF
which yum && yum install -y ethtool && exit
which apt-get && apt-get update && apt-get install -y ethtool && exit
which apk && apk add ethtool && exit
:
EOF
    hr
    docker_exec check_linux_interface.pl -i eth0 -v -e -d Full
    echo "sleeping for 1 sec before second run to check stats code path + re-load from state file"
    sleep 1
    docker_exec check_linux_interface.pl -i eth0 -v -e -d Full
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
    #docker_exec check_linux_timezone.pl -T UTC -Z /usr/share/zoneinfo/UTC -A UTC -v
    # Alpine doesn't have zoneinfo installation
    docker_exec check_linux_timezone.pl -T UTC -Z /etc/localtime -A UTC -v
    hr
    if [ "$distro" = "centos" ]; then
        docker-compose exec "centos-github" yum makecache fast
        hr
        docker_exec check_yum.pl -C -v -t 30
        hr
        docker_exec check_yum.pl -C --all-updates -v -t 30 || :
        hr
        docker_exec check_yum.py -C -v -t 30
        hr
        docker_exec check_yum.py -C --all-updates -v -t 30 || :
        hr
    fi
    #delete_container
    docker-compose down
    echo
}

if [ $# -gt 1 ]; then
    test_linux "$1" "$2"
elif [ $# -gt 0 ]; then
    test_linux "$1" "latest"
else
    section "CentOS"
    for version in $(ci_sample latest); do
        test_linux centos "$version"
    done

    section "Ubuntu"
    for version in $(ci_sample latest); do
        test_linux ubuntu "$version"
    done

    section "Debian"
    for version in $(ci_sample latest); do
        test_linux debian "$version"
    done

    section "Alpine"
    for version in $(ci_sample latest); do
        test_linux alpine "$version"
    done
fi

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
