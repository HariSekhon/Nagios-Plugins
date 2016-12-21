#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-08 14:38:37 +0000 (Thu, 08 Dec 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "$0")" && pwd)"

cd "$srcdir/.."

. "bash-tools/docker.sh"

section "Docker Image"

export DOCKER_IMAGE="harisekhon/nagios-plugins"

if is_docker_available; then
    docker pull "$DOCKER_IMAGE"
    set +e
    docker run --rm -e "DEBUG=$DEBUG" "$DOCKER_IMAGE" check_ssl_cert.pl --help
    check_exit_code 3
    set -e
    docker run --rm -e "DEBUG=$DEBUG" "$DOCKER_IMAGE" check_ssl_cert.pl -H google.com
    docker run --rm -e "DEBUG=$DEBUG" "$DOCKER_IMAGE" tests/help.sh
fi
