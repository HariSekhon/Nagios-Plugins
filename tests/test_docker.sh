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
DEBUG="${DEBUG:-}"
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "$0")" && pwd)"

cd "$srcdir/.."

. "bash-tools/docker.sh"
. "bash-tools/utils.sh"

section "Docker Image"

export DOCKER_IMAGE="harisekhon/nagios-plugins"
export DOCKER_IMAGES=(harisekhon/tools harisekhon/pytools harisekhon/nagios-plugins:centos harisekhon/nagios-plugins:debian harisekhon/nagios-plugins:ubuntu harisekhon/nagios-plugins:alpine)
if is_CI; then
    export DOCKER_IMAGES="$(ci_sample ${DOCKER_IMAGES[*]})"
fi

if is_docker_available; then
    [ -n "${NO_DOCKER:-}" ] && exit 0
    if [ -z "${NO_PULL:-}" ]; then
        docker pull "$DOCKER_IMAGE"
        for image in ${DOCKER_IMAGES[*]}; do
            docker pull "$image"
        done
    fi
    hr
    echo "./check_docker_image.py --docker-image $DOCKER_IMAGE:latest"
    ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest"
    hr
    for image in ${DOCKER_IMAGES[*]}; do
        max_size=$((600 * 1024 * 1024))
        if grep nagios <<< "$image"; then
            max_size=$((800 * 1024 * 1024))
        fi
        if ! grep ':' <<< "$image"; then
            image="$image:latest"
        fi
        echo "./check_docker_image.py --docker-image $image --warning $max_size"
        ./check_docker_image.py --docker-image "$image" --warning "$max_size"
        hr
    done
    echo "./check_docker_image.py --docker-image $DOCKER_IMAGE:latest --warning $((800 * 1024 * 1024))"
    ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --warning $((800 * 1024 * 1024))
    hr
    echo "checking thresholds fail as expected:"
    set +e
    echo "./check_docker_image.py --docker-image $DOCKER_IMAGE:latest --warning $((300 * 1024 * 1024))"
    ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --warning $((300 * 1024 * 1024))
    check_exit_code 1
    hr
    echo "./check_docker_image.py --docker-image $DOCKER_IMAGE:latest --critical $((300 * 1024 * 1024))"
    ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --critical $((300 * 1024 * 1024))
    check_exit_code 2
    hr
    # This fails set -e, possibly because docker images command is interrupted by the abrupt exit of awk
    id="$(docker images | awk "/^${DOCKER_IMAGE//\//\\/}.*latest/{print \$3; exit}")"
    set -e
    echo "testing against expected id of $id"
    echo "./check_docker_image.py --docker-image $DOCKER_IMAGE:latest --id $id"
    ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "$id"
    hr
    echo "testing intentional id failure:"
    echo "./check_docker_image.py --docker-image $DOCKER_IMAGE:latest --id wrongid"
    set +e
    ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "wrongid"
    check_exit_code 2
    set -e
    hr
    set +e
    echo "docker run --rm -e DEBUG='$DEBUG' '$DOCKER_IMAGE' check_ssl_cert.pl --help"
    docker run --rm -e DEBUG="$DEBUG" "$DOCKER_IMAGE" check_ssl_cert.pl --help
    check_exit_code 3
    set -e
    hr
    echo "docker run --rm -e DEBUG='$DEBUG' '$DOCKER_IMAGE' check_ssl_cert.pl -H google.com"
    docker run --rm -e DEBUG="$DEBUG" "$DOCKER_IMAGE" check_ssl_cert.pl -H google.com
    echo
    echo "docker run --rm -e DEBUG='$DEBUG' -e NO_GIT=1 -e TRAVIS='${TRAVIS:-}' '$DOCKER_IMAGE' tests/help.sh"
    docker run --rm -e DEBUG="$DEBUG" -e NO_GIT=1 -e TRAVIS="${TRAVIS:-}" "$DOCKER_IMAGE" tests/help.sh
fi
