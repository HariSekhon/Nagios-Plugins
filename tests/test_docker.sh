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

# shellcheck disable=SC1090
. "$srcdir/../bash-tools/lib/docker.sh"

# shellcheck disable=SC1090
. "$srcdir/../bash-tools/lib/utils.sh"

section "Docker Image"

export DOCKER_IMAGE="harisekhon/nagios-plugins"
export DOCKER_IMAGE_TAGS="latest centos debian ubuntu alpine"
export DOCKER_IMAGES=(harisekhon/tools harisekhon/pytools harisekhon/nagios-plugins)
if is_CI; then
    # want splitting
    # shellcheck disable=SC2086,SC2178
    DOCKER_IMAGES="$(ci_sample ${DOCKER_IMAGES[*]})"
    export DOCKER_IMAGES
fi

stdout="/dev/stdout"
if is_CI; then
    stdout="/dev/null"
fi

if is_docker_available; then
    [ -n "${NO_DOCKER:-}" ] && exit 0

    if is_CI; then
        # want splitting
        # shellcheck disable=SC2086
        trap '
            docker_rmi_grep harisekhon/nagios-plugins || :
            docker_rmi_grep harisekhon/tools || :
            docker_rmi_grep harisekhon/pytools || :
            docker_rmi_grep harisekhon/perl-tools || :
            docker_rmi_grep harisekhon/bash-tools || :
        ' $TRAP_SIGNALS
    fi

    # ============================================================================ #

    run ./check_docker_api_ping.py

    echo "checking connection refused:"
    DOCKER_HOST=tcp://127.0.0.1:23760 ERRCODE=2 run_grep 'Connection refused' ./check_docker_api_ping.py

    # ============================================================================ #

    run ./check_docker_version.py

    run ./check_docker_version.py --expected '^\d+\.\d+|\+azure$'

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

    container=nagios-plugins-container-test
    echo "deleting test docker container '$container' if already exists:"
    docker rm -f "$container" 2>/dev/null || :
    echo "creating test docker container '$container':"
    docker run -d --name "$container" alpine top
    hr

    run ./check_docker_container_status.py --container "$container"
    run ./check_docker_container_status.py -v -C "$container"

    run ./check_docker_containers.py -c 0
    run_fail 2 ./check_docker_containers.py --running -c 0
    run_fail 2 ./check_docker_containers.py --total -c 0

    docker pause "$container"

    run_fail 1 ./check_docker_container_status.py --container "$container"
    run_fail 1 ./check_docker_container_status.py -v -C "$container"

    run_fail 2 ./check_docker_containers.py --paused -c 0
    run_fail 2 ./check_docker_containers.py --total -c 0

    docker stop "$container"

    run_fail 2 ./check_docker_container_status.py --container "$container"
    run_fail 2 ./check_docker_container_status.py -v -C "$container"

    run_fail 2 ./check_docker_containers.py --stopped -c 0
    run_fail 2 ./check_docker_containers.py --total -c 0

    docker rm "$container"
    hr

    run_fail 2 ./check_docker_container_status.py --container "$container"
    run_fail 2 ./check_docker_container_status.py -v -C "$container"

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

    echo "Creating test volume to test volumes thresholds:"
    docker volume create --name nagios-plugins-test || :
    run_fail 1 ./check_docker_volumes.py -w 0
    run_fail 2 ./check_docker_volumes.py -c 0
    echo "Deleting test volume:"
    docker volume rm nagios-plugins-test

    echo "checking connection refused:"
    DOCKER_HOST=tcp://127.0.0.1:23760 ERRCODE=2 run_grep 'Connection refused' ./check_docker_volumes.py

    # ============================================================================ #

    service=nagios-plugins-service-test

    if ./check_docker_swarm_enabled.py; then

        # rather than just run++ above, run it again so run prints the command and result with separator, not just the result
        run ./check_docker_swarm_enabled.py

        run ./check_docker_swarm_node_active.py

        run ./check_docker_swarm_is_manager.py

        echo "deleting test docker service '$service' if already exists:"
        docker service rm "$service" 2>/dev/null || :
        echo "creating test docker server '$service':"
        docker service create --name "$service" --replicas 2 alpine top
        hr

        run ./check_docker_swarm_error.py

        run ./check_docker_swarm_nodes.py
        run ./check_docker_swarm_nodes.py --manager

        set +o pipefail
        echo "determining number of Docker Swarm worker and manager nodes:"
        num_worker_nodes=$(./check_docker_swarm_nodes.py | sed 's/^[^=]*= //;s/ .*//')
        echo "determined number of Docker Swarm worker nodes to be '$num_worker_nodes'"
        num_manager_nodes=$(./check_docker_swarm_nodes.py --manager | sed 's/^[^=]*= //;s/ .*//')
        echo "determined number of Docker Swarm manager nodes to be '$num_manager_nodes'"
        set -o pipefail
        ((worker_threshold=num_worker_nodes+1))
        ((manager_threshold=num_manager_nodes+1))

        run_fail 1 ./check_docker_swarm_nodes.py -w "$worker_threshold"
        run_fail 2 ./check_docker_swarm_nodes.py -c "$worker_threshold"
        run_fail 1 ./check_docker_swarm_nodes.py -w "$manager_threshold" --manager
        run_fail 2 ./check_docker_swarm_nodes.py -c "$manager_threshold" --manager

        run ./check_docker_swarm_services.py

        run_fail 1 ./check_docker_swarm_services.py -w 0

        run_fail 2 ./check_docker_swarm_services.py -w 0 -c 0

        run ./check_docker_swarm_service_status.py --service "$service"

        run ./check_docker_swarm_service_status.py --service "$service" -v

        run_fail 1 ./check_docker_swarm_service_status.py --service "$service" -U 60

        run ./check_docker_swarm_service_status.py --service "$service" -w 2:2 -c 2:2

        run_fail 1 ./check_docker_swarm_service_status.py --service "$service" -w 3 -c 2:2

        run_fail 2 ./check_docker_swarm_service_status.py --service "$service" -w 2:2 -c 3

        echo "recreating test docker server '$service' as a global service:"
        docker service rm "$service"
        docker service create --name "$service" --mode global alpine top
        hr

        run ./check_docker_swarm_service_status.py --service "$service"

        run_fail 1 ./check_docker_swarm_service_status.py --service "$service" -U 60

        run_fail 2 ./check_docker_swarm_service_status.py --service "$service" -w 2:2

        docker service rm "$service"
        hr
    else
        run_fail 2 ./check_docker_swarm_enabled.py

        run_fail 2 ./check_docker_swarm_node_active.py

        run_fail 2 ./check_docker_swarm_is_manager.py

        run_fail 2 ./check_docker_swarm_error.py

        run_fail 2 ./check_docker_swarm_nodes.py
        run_fail 2 ./check_docker_swarm_nodes.py --manager

        run_fail 2 ./check_docker_swarm_nodes.py
        run_fail 2 ./check_docker_swarm_nodes.py --manager
        run_fail 2 ./check_docker_swarm_nodes.py -w 1
        run_fail 2 ./check_docker_swarm_nodes.py -w 1 --manager
        run_fail 2 ./check_docker_swarm_nodes.py -c 1
        run_fail 2 ./check_docker_swarm_nodes.py -c 1 --manager

        run_fail 2 ./check_docker_swarm_services.py

        run_fail 2 ./check_docker_swarm_service_status.py --service "$service"
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
    run ./older/check_docker_image.py --docker-image "$DOCKER_IMAGE:latest"

    for image in ${DOCKER_IMAGES[*]}; do
        max_size=$((2000 * 1024 * 1024))
#        if grep nagios <<< "$image"; then
#            max_size=$((600 * 1024 * 1024))
#        fi
        if ! [[ "$image" =~ : ]]; then
            image="$image:latest"
        fi
        run ./check_docker_image.py --docker-image "$image" --warning "$max_size"
        run ./older/check_docker_image.py --docker-image "$image" --warning "$max_size"
    done
    for tag in $DOCKER_IMAGE_TAGS; do
        run ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --warning "$max_size"
        run ./older/check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --warning "$max_size"

        echo "checking thresholds fail as expected:"
        run_fail 1 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --warning $((200 * 1024 * 1024))
        run_fail 1 ./older/check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --warning $((200 * 1024 * 1024))

        run_fail 2 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --critical $((200 * 1024 * 1024))
        run_fail 2 ./older/check_docker_image.py --docker-image "$DOCKER_IMAGE:$tag" --critical $((200 * 1024 * 1024))
    done
    echo "getting docker image id"
    # This fails set -e, possibly because docker images command is interrupted by the abrupt exit of awk
    set +e
    id="$(docker images | awk "/^${DOCKER_IMAGE//\//\\/}.*latest/{print \$3; exit}")"
    echo "determined docker id for $DOCKER_IMAGE:latest to be $id"
    set -e
    if [ -z "$id" ]; then
        echo "FAILED to get docker image id, debug pipeline"
        exit 1
    fi
    hr
    echo "testing against expected id of $id"
    run ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "sha256:${id:0:10}"
    run ./older/check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "$id"

    echo "testing intentional id failure:"
    run_fail 2 ./check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "wrongid"
    run_fail 2 ./older/check_docker_image.py --docker-image "$DOCKER_IMAGE:latest" --id "wrongid"

    run_usage docker run --rm -e DEBUG "$DOCKER_IMAGE" check_ssl_cert.pl --help

    run docker run --rm -e DEBUG "$DOCKER_IMAGE" check_ssl_cert.pl -H google.com -w 2 -c 1

    echo
    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Docker tests"
    echo
    echo "now checking all programs within the docker image run --help without missing dependencies:"
    run docker run --rm -e DEBUG -e NO_GIT=1 -e TRAVIS="${TRAVIS:-}" "$DOCKER_IMAGE" tests/help.sh
fi
