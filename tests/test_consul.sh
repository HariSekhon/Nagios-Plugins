#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-26 23:36:03 +0000 (Tue, 26 Jan 2016)
#
#  https://github.com/harisekhon
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  http://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. utils.sh

export DOCKER_CONTAINER="nagios-plugins-consul"

if ! which docker &>/dev/null; then
    echo 'WARNING: Docker not found, skipping Consul checks!!!'
    exit 0
fi

echo "Setting up test Consul container"
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    echo "Starting Docker Consul test container"
    docker run -d --name "$DOCKER_CONTAINER" -p 8500:8500 harisekhon/consul agent -data-dir /tmp -client 0.0.0.0
    sleep 5
else
    echo "Docker Consul test container already running"
fi

hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
