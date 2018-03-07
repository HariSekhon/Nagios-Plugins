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
export DOCKER_IMAGE_TAGS="latest centos debian ubuntu alpine"
export DOCKER_IMAGES=(harisekhon/tools harisekhon/pytools harisekhon/nagios-plugins)
if is_CI; then
    export DOCKER_IMAGES="$(ci_sample ${DOCKER_IMAGES[*]})"
fi

stdout="/dev/stdout"
if is_CI; then
    stdout="/dev/null"
fi

if is_docker_available; then
    [ -n "${NO_DOCKER:-}" ] && exit 0
    # ============================================================================ #

    run ./check_docker_api_ping.py

    echo "checking connection refused:"
    DOCKER_HOST=tcp://127.0.0.1:23760 ERRCODE=2 run_grep 'Connection refused' ./check_docker_api_ping.py

    # ============================================================================ #

    run ./check_docker_version.py

    run ./check_docker_version.py --expected '^1.+'

    run_fail 2 ./check_docker_version.py --expected 'wrong-version'

    echo "checking connection refused:"
    DOCKER_HOST=tcp://127.0.0.1:23760 ERRCODE=2 run_grep 'Connection refused' ./check_docker_version.py

    # ============================================================================ #

    if docker info | grep -i 'Swarm: active'; then
        run ./check_docker_swarm_version.py

        run ./check_docker_swarm_version.py --expected '^1.+'
    else
        run_fail 2 ./check_docker_swarm_version.py

        run_fail 2 ./check_docker_swarm_version.py --expected '^1.+'
    fi

    run_fail 2 ./check_docker_swarm_version.py --expected 'wrong-version'

    echo "checking connection refused:"
    DOCKER_HOST=tcp://127.0.0.1:23760 ERRCODE=2 run_grep 'Connection refused' ./check_docker_swarm_version.py

    # ============================================================================ #

    run ./check_docker_containers.py

    run ./check_docker_containers.py --running -w 10000 -c 100000
    run ./check_docker_containers.py --paused -w 0
    run ./check_docker_containers.py --stopped -w 1000
    run ./check_docker_containers.py --total -w 100000

    docker run -d --name docker-containers-test redis:alpine

    run ./check_docker_containers.py -c 0
    run_fail 2 ./check_docker_containers.py --running -c 0
    run_fail 2 ./check_docker_containers.py --total -c 0

    docker pause docker-containers-test

    run_fail 2 ./check_docker_containers.py --paused -c 0
    run_fail 2 ./check_docker_containers.py --total -c 0

    docker stop docker-containers-test

    run_fail 2 ./check_docker_containers.py --stopped -c 0
    run_fail 2 ./check_docker_containers.py --total -c 0

    docker rm docker-containers-test

    echo "checking connection refused:"
    DOCKER_HOST=tcp://127.0.0.1:23760 ERRCODE=2 run_grep 'Connection refused' ./check_docker_containers.py

    # ============================================================================ #

    run ./check_docker_networks.py

    run_fail 1 ./check_docker_networks.py -w 1
    run_fail 2 ./check_docker_networks.py -c 1

    echo "checking connection refused:"
    DOCKER_HOST=tcp://127.0.0.1:23760 ERRCODE=2 run_grep 'Connection refused' ./check_docker_networks.py

    # ============================================================================ #

    run ./check_docker_volumes.py

    run_fail 1 ./check_docker_volumes.py -w 1
    run_fail 2 ./check_docker_volumes.py -c 1

    echo "checking connection refused:"
    DOCKER_HOST=tcp://127.0.0.1:23760 ERRCODE=2 run_grep 'Connection refused' ./check_docker_volumes.py

    # ============================================================================ #

    run++
    if ./check_docker_swarm_enabled.py; then
        run ./check_docker_swarm_node_active.py

        run ./check_docker_swarm_is_manager.py

        run ./check_docker_swarm_error.py

        run ./check_docker_swarm_nodes.py
        run ./check_docker_swarm_nodes.py --manager

        # assumption we are running a single swarm node for testing
        # TODO: parse out actual number and set that to the threshold
        run_fail 1 ./check_docker_swarm_nodes.py -w 2
        run_fail 2 ./check_docker_swarm_nodes.py -c 2
        run_fail 1 ./check_docker_swarm_nodes.py -w 2 --manager
        run_fail 2 ./check_docker_swarm_nodes.py -c 2 --manager

        run ./check_docker_services.py
    else
        run_fail 2 ./check_docker_swarm_enabled.py

        run_fail 2 ./check_docker_swarm_node_active.py

        run_fail 2 ./check_docker_swarm_is_manager.py

        run_fail 2 ./check_docker_swarm_error.py

        run_fail 2 ./check_docker_swarm_nodes.py
        run_fail 2 ./check_docker_swarm_nodes.py --manager

        # TODO: parse out actual number and set that to the threshold
        run_fail 2 ./check_docker_swarm_nodes.py -w 2
        run_fail 2 ./check_docker_swarm_nodes.py -c 2
        run_fail 2 ./check_docker_swarm_nodes.py -w 2 --manager
        run_fail 2 ./check_docker_swarm_nodes.py -c 2 --manager

        run_fail 2 ./check_docker_services.py
    fi

    # ============================================================================ #

    if [ -z "${NO_PULL:-}" ]; then
        echo docker pull "$DOCKER_IMAGE"
        docker pull "$DOCKER_IMAGE" > $stdout
        for image in ${DOCKER_IMAGES[*]}; do
            echo docker pull "$image"
            docker pull "$image" > $stdout
        done
        for tag in $DOCKER_IMAGE_TAGS; do
            echo docker pull "$DOCKER_IMAGE:$tag"
            docker pull "$DOCKER_IMAGE:$tag" > $stdout
        done
    fi
    hr

    run ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest"
    run ./check_docker_image_old.py --docker-image "$DOCKER_IMAGE:latest"

    for image in ${DOCKER_IMAGES[*]}; do
        max_size=$((600 * 1024 * 1024))
#        if grep nagios <<< "$image"; then
#            max_size=$((600 * 1024 * 1024))
#        fi
        if ! [[ "$image" =~ : ]]; then
            image="$image:latest"
        fi
        run ./check_docker_image.py --docker-image "$image" --warning "$max_size"
        run ./check_docker_image_old.py --docker-image "$image" --warning "$max_size"
    done
    for tag in $DOCKER_IMAGE_TAGS; do
        run ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --warning $((800 * 1024 * 1024))
        run ./check_docker_image_old.py --docker-image "$DOCKER_IMAGE:$tag" --warning $((800 * 1024 * 1024))

        echo "checking thresholds fail as expected:"
        run_fail 1 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --warning $((300 * 1024 * 1024))
        run_fail 1 ./check_docker_image_old.py --docker-image "$DOCKER_IMAGE:$tag" --warning $((300 * 1024 * 1024))

        run_fail 2 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --critical $((300 * 1024 * 1024))
        run_fail 2 ./check_docker_image_old.py --docker-image "$DOCKER_IMAGE:$tag" --critical $((300 * 1024 * 1024))
    done
    echo "getting docker image id"
    # This fails set -e, possibly because docker images command is interrupted by the abrupt exit of awk
    set +e
    id="$(docker images | awk "/^${DOCKER_IMAGE//\//\\/}.*latest/{print \$3; exit}")"
    set -e
    if [ -z "$id" ]; then
        echo "FAILED to get docker image id, debug pipeline"
        exit 1
    fi
    hr
    echo "testing against expected id of $id"
    run ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "$id"
    run ./check_docker_image_old.py --docker-image "$DOCKER_IMAGE:latest" --id "$id"

    echo "testing intentional id failure:"
    run_fail 2 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "wrongid"
    run_fail 2 ./check_docker_image_old.py --docker-image "$DOCKER_IMAGE:latest" --id "wrongid"

    run_usage docker run --rm -e DEBUG="$DEBUG" "$DOCKER_IMAGE" check_ssl_cert.pl --help

    run docker run --rm -e DEBUG="$DEBUG" "$DOCKER_IMAGE" check_ssl_cert.pl -H google.com

    echo
    echo "Completed $run_count Docker tests"
    echo
    echo "now checking all programs within the docker image run --help without missing dependencies:"
    run docker run --rm -e DEBUG="$DEBUG" -e NO_GIT=1 -e TRAVIS="${TRAVIS:-}" "$DOCKER_IMAGE" tests/help.sh
fi
