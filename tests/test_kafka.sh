#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-26 23:36:03 +0000 (Tue, 26 Jan 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

echo "
# ============================================================================ #
#                                   K a f k a
# ============================================================================ #
"

export DOCKER_IMAGE="harisekhon/kafka_scala-2.10"

KAFKA_HOST="${DOCKER_HOST:-${KAFKA_HOST:-${HOST:-localhost}}}"
KAFKA_HOST="${KAFKA_HOST##*/}"
KAFKA_HOST="${KAFKA_HOST%%:*}"
export KAFKA_HOST
echo "using docker address '$KAFKA_HOST'"
export KAFKA_PORT="${KAFKA_PORT:-9092}"
export KAFKA_TOPIC="nagios-plugins-test"

export DOCKER_CONTAINER="nagios-plugins-kafka"

if ! is_docker_available; then
    echo 'WARNING: Docker unavailable, skipping kafka checks!!!'
    exit 0
fi

# needs to be longer than 10 to allow Kafka to settle so topic creation works
startupwait=20
is_travis && let startupwait+=20

echo "Setting up Apache Kafka test container"
hr
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! is_docker_container_running "$DOCKER_CONTAINER"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Kafka_scala-2.10 test container"
    docker run -d --name "$DOCKER_CONTAINER" -p $KAFKA_PORT:$KAFKA_PORT "$DOCKER_IMAGE"
    echo "waiting $startupwait seconds for Kafka to start up and settle"
    sleep $startupwait
    echo "creating Kafka test topic"
    docker exec -ti "$DOCKER_CONTAINER" kafka-topics.sh --zookeeper localhost:2181 --create --replication-factor 1 --partitions 1 --topic "$KAFKA_TOPIC"
else
    echo "Docker test container '$DOCKER_CONTAINER' already running"
fi

hr
$perl -T $I_lib ./check_kafka.pl -T "$KAFKA_TOPIC" -v --list-topics || :
hr
$perl -T $I_lib ./check_kafka.pl -T "$KAFKA_TOPIC" -v
hr
echo
if [ -z "${NODELETE:-}" ]; then
    echo -n "Deleting container "
    docker rm -f "$DOCKER_CONTAINER"
fi
echo; echo
