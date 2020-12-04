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

# using Docker now so runs on Mac too
#[ `uname -s` = "Linux" ] || exit 0

if [ -z "${FORCE_YUM_CHECKS:-}" ]; then
    # XXX: NO LONGER USED, DONE AS PART OF LINUX CHECKS NOW
    return 0 &>/dev/null || :
    exit 0
fi

section "Y u m"

check_docker_available

startupwait 0

export DOCKER_MOUNT_DIR="/pl"

section2 "Setting up CentOS test container"

distro=centos

export DOCKER_CONTAINER="nagios-plugins_$distro-github_1"
export COMPOSE_FILE="$srcdir/docker/$distro-github-docker-compose.yml"

docker_compose_pull

docker-compose up -d --remove-orphans

docker-compose exec "centos-github" yum makecache fast

if [ -n "${NOTESTS:-}" ]; then
    exit 0
fi

ERRCODE="0 1 2" docker_exec older/check_yum.pl -v -t 120
ERRCODE="0 1 2" docker_exec older/check_yum.pl -C -v -t 60

ERRCODE="0 1 2" docker_exec older/check_yum.pl --all-updates -v -t 120
ERRCODE="0 1 2" docker_exec older/check_yum.pl -C --all-updates -v -t 60

ERRCODE="0 1 2" docker_exec check_yum.py -v -t 120
ERRCODE="0 1 2" docker_exec check_yum.py -C -v -t 60

ERRCODE="0 1 2" docker_exec check_yum.py --all-updates -v -t 120
ERRCODE="0 1 2" docker_exec check_yum.py -C --all-updates -v -t 60

# defined and tracked in bash-tools/lib/utils.sh
# shellcheck disable=SC2154
echo "Completed $run_count Yum tests"
hr
[ -n "${KEEPDOCKER:-}" ] ||
docker-compose down
echo; echo

if is_CI; then
    docker_image_cleanup
    echo
fi
