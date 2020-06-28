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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

#[ `uname -s` = "Linux" ] || exit 0

section "L i n u x"

check_docker_available

export DOCKER_MOUNT_DIR="/pl"

valid_distros=(alpine centos debian ubuntu)

# TODO: build specific versions to test for CentOS 6 + 7, Ubuntu 14.04 + 16.04, Debian Wheezy + Jessie, Alpine builds
test_linux(){
    local distro="$1"
    local version="$2"
    section2 "Setting up Linux $distro $version test container"
    export DOCKER_CONTAINER="nagios-plugins_$distro-github_1"
    export COMPOSE_FILE="$srcdir/docker/$distro-github-docker-compose.yml"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "mounting ramdisks for read only disk mounts check:"
    #docker exec "$DOCKER_CONTAINER" yum install -y net-tools
    # this requires --privileged=true to work
    docker exec -i "$DOCKER_CONTAINER" bash <<EOF
    mkdir -pv /mnt/ramdisk{1,2}
    for x in 1 2; do umount /mnt/ramdisk\$x &>/dev/null; done
    mount -t tmpfs -o size=1m    tmpfs /mnt/ramdisk1
    mount -t tmpfs -o size=1m,ro tmpfs /mnt/ramdisk2
EOF
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi

    docker_exec check_linux_disk_mounts_read_only.py --include /mnt/ramdisk1

    # TODO: extend docker_exec to support $ERRCODE then enable this
    #ERRCODE=2 docker_exec check_linux_disk_mounts_read_only.py --include '/mnt/ramdisk?'
    docker_exec check_linux_disk_mounts_read_only.py || :

    docker_exec check_linux_disk_mounts_read_only.py --include '/mnt/ramdisk?' || :

    docker_exec check_linux_disk_mounts_read_only.py -e /mnt/ramdisk2

    docker_exec check_disk_write.pl -d .

    docker_exec check_linux_auth.pl -u root -g root -v

    # setting this high now because my workstation is heavily loaded with docker builds and want this to pass
    docker_exec check_linux_context_switches.pl || : ; sleep 1; docker_exec check_linux_context_switches.pl -w 50000 -c 70000

    docker_exec check_linux_duplicate_IDs.pl

    docker_exec check_linux_hugepages_disabled.py

    # temporary fix until slow DockerHub automated builds trickle through ethtool in docker images
#    docker exec -i "$DOCKER_CONTAINER" sh <<EOF
#which yum && yum install -y ethtool net-tools && exit
#which apt-get && apt-get update && apt-get install -y ethtool net-tools && exit
#which apk && apk add ethtool && exit
#:
#EOF
#    hr

    docker_exec check_linux_interface.pl -i eth0 -v -e -d Full

    echo "sleeping for 1 sec before second run to check stats code path + re-load from state file:"
    sleep 1
    echo
    docker_exec check_linux_interface.pl -i eth0 -v -e -d Full

    # making this much higher so it doesn't trip just due to test system load
    docker_exec check_linux_load_normalized.pl -w 99 -c 99

    docker_exec check_linux_load_normalized.pl -w 99 -c 99 --cpu-cores-perfdata

    docker_exec check_linux_ram.py -v -w 20% -c 10%

    docker_exec check_linux_system_file_descriptors.pl

    #docker_exec check_linux_timezone.pl -T UTC -Z /usr/share/zoneinfo/UTC -A UTC -v

    # Alpine doesn't have zoneinfo installation
    docker_exec check_linux_timezone.pl -T UTC -Z /etc/localtime -A UTC -v

    if [ "$distro" = "centos" ]; then
        docker-compose exec "centos-github" yum makecache fast
        hr

        ERRCODE="0 1 2" docker_exec older/check_yum.pl -C -v -t 30

        ERRCODE="0 1 2" docker_exec older/check_yum.pl -C --all-updates -v -t 30

        ERRCODE="0 1 2" docker_exec check_yum.py -C -v -t 30

        ERRCODE="0 1 2" docker_exec check_yum.py -C --all-updates -v -t 30
    fi
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Linux tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

if [ $# -gt 1 ]; then
    if ! [[ ${valid_distros[*]} =~ $1 ]]; then
        echo "INVALID distro argument given, must be one of: ${valid_distros[*]}"
        exit 1
    fi
    distro="$1"
    shift
    for version in "$@"; do
        test_linux "$distro" "$version"
    done
elif [ $# -eq 1 ] && [ "${1:-}" != "latest" ]; then
    if [[ ${valid_distros[*]} =~ $1 ]]; then
        test_linux "$1" "latest"
    else
        echo "INVALID distro argument given, must be one of: ${valid_distros[*]}"
        exit 1
    fi
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
