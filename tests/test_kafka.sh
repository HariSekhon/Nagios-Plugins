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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "K a f k a"

# TODO: latest container 2.11_0.10 doesn't work yet, no leader takes hold
#export KAFKA_VERSIONS="${*:-2.11_0.10 2.11_0.10 latest}"
export KAFKA_VERSIONS="${*:-${KAFKA_VERSIONS:-2.10-0.8 2.11-0.8 2.10-0.9 2.11-0.9 latest}}"

KAFKA_HOST="${DOCKER_HOST:-${KAFKA_HOST:-${HOST:-localhost}}}"
KAFKA_HOST="${KAFKA_HOST##*/}"
KAFKA_HOST="${KAFKA_HOST%%:*}"
export KAFKA_HOST

export KAFKA_PORT="${KAFKA_PORT:-9092}"

export DOCKER_IMAGE="harisekhon/kafka"

check_docker_available

trap_debug_env kafka

export KAFKA_TOPIC="nagios-plugins-kafka-test"

# needs to be longer than 10 to allow Kafka to settle so topic creation works
startupwait 20

test_kafka(){
    local version="$1"
    section2 "Setting up Apache Kafka $version test container"
    export ADVERTISED_HOSTNAME="$KAFKA_HOST"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    when_ports_available "$KAFKA_HOST" "$KAFKA_PORT"
    hr
    if [ -z "${NOSETUP:-}" ]; then
        echo "checking if Kafka topic already exists:"
        set +o pipefail
        if docker-compose exec "$DOCKER_SERVICE" kafka-topics.sh --zookeeper localhost:2181 --list | tee /dev/stderr | grep -q "^[[:space:]]*${KAFKA_TOPIC}[[:space:]]*$"; then
            echo "Kafka topic $KAFKA_TOPIC already exists, continuing"
        else
            echo "creating Kafka test topic:"
            SECONDS=0
            while true; do
                # Older versions of Kafka eg. 0.8 seem to return 0 even when this fails so check the output instead
                docker-compose exec "$DOCKER_SERVICE" kafka-topics.sh --zookeeper localhost:2181 --create --replication-factor 1 --partitions 1 --topic "$KAFKA_TOPIC" | tee /dev/stderr | grep -q -e 'Created topic' -e 'already exists' && break
                if [ "$SECONDS" -gt 20 ]; then
                    echo "FAILED: kafka topic still not able to be created after 20 secs"
                    exit 1
                fi
                echo "retrying for Kafka topic to be successfully created (waited $SECONDS secs)"
                sleep 1
            done
        fi
        set -o pipefail
    fi
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    hr
    if [ "$version" = "latest" ]; then
        echo "latest version, fetching latest version from DockerHub master branch"
        # TODO: improve this for Kafka specifically
        local version
        version="$(dockerhub_latest_version kafka)"
        echo "expecting version '$version'"
    fi
    hr
    set +e
    # -T often returns no output, just strip leading escape chars instead
    found_version="$(docker-compose exec "$DOCKER_SERVICE" /bin/sh -c 'ls -d /kafka_*' | tail -n1 | tr -d '$\r' | sed 's/.*\/kafka_//; s/\.[[:digit:]]*\.[[:digit:]]*$//')"
    echo "found version $found_version"
    set -e
    # TODO: make container and official versions align
    #if [[ "${found_version//-/_}" != ${version//-/_}* ]]; then
    if [[ "$found_version" != "$version"* ]]; then
        echo "Docker container version does not match expected version! (found '$found_version', expected '$version')"
        exit 1
    fi
    hr
    run ./check_kafka.py -H "$KAFKA_HOST" -P "$KAFKA_PORT" -T "$KAFKA_TOPIC" -v

    run ./check_kafka.py -H "$KAFKA_HOST" -P "$KAFKA_PORT" -v

    run ./check_kafka.py -H "$KAFKA_HOST" -v

    run ./check_kafka.py -B "$KAFKA_HOST" -v

    run ./check_kafka.py -B "$KAFKA_HOST:$KAFKA_PORT" -v

    run ./check_kafka.py -B "$KAFKA_HOST" -P "$KAFKA_PORT" -v

    KAFKA_BROKERS="$KAFKA_HOST" \
    run ./check_kafka.py -v

    echo "checking default port is overridden by more specific port per broker inside KAFKA_BROKERS by setting default port to the wrong port and checking it still succeeds:"
    KAFKA_BROKERS="$KAFKA_HOST:$KAFKA_PORT" \
    run ./check_kafka.py -P "999" -v

    run ./check_kafka.py -v

    echo "checking default port works by setting it to the wrong port and testing for failure expecting NoBrokersAvailable:"
    ERRCODE=2 run_grep "NoBrokersAvailable" ./check_kafka.py -B "$KAFKA_HOST" -P "999" -v

    run_fail 3 ./check_kafka.py -B "$KAFKA_HOST:$KAFKA_PORT" -v --list-topics

    run_fail 3 ./check_kafka.py -B "$KAFKA_HOST:$KAFKA_PORT" -v -T "$KAFKA_TOPIC" --list-partitions

    run_fail 3 ./check_kafka.py -B "$KAFKA_HOST:$KAFKA_PORT" -v --list-partitions

    ERRCODE=2 run_grep "NoBrokersAvailable" ./check_kafka.py -B "localhost:9999" -v -T "$KAFKA_TOPIC"

    ERRCODE=2 run_grep "NoBrokersAvailable" ./check_kafka.py -B "localhost:9999" -v -T "$KAFKA_TOPIC" --list-partitions

    run ./check_kafka.py -B "$KAFKA_HOST:$KAFKA_PORT" -T "$KAFKA_TOPIC" -v

#    ./check_kafka_topic_exists.py -B "$KAFKA_HOST:$KAFKA_PORT" -T "$KAFKA_TOPIC" -v

#    run_fail 2 ./check_kafka_topic_exists.py -B "$KAFKA_HOST:$KAFKA_PORT" -T "nonexistenttopic" -v

#    run_fail 2 ./check_kafka_topic_exists.py -B "localhost:9999" -T "$KAFKA_TOPIC" -v

    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    run_fail 3 "$perl" -T ./check_kafka.pl -v --list-topics

    run_fail 3 "$perl" -T ./check_kafka.pl -T "$KAFKA_TOPIC" -v --list-partitions

    run_fail 3 "$perl" -T ./check_kafka.pl -v --list-partitions

    ERRCODE=2 run_grep "Cannot get metadata" "$perl" -T ./check_kafka.pl -H localhost -P 9999 -v --list-partitions

    ERRCODE=2 run_grep "Cannot get metadata" "$perl" -T ./check_kafka.pl -H localhost -P 9999 -v

    # shellcheck disable=SC2097,SC2098
    KAFKA_BROKERS="$KAFKA_HOST:$KAFKA_PORT" KAFKA_HOST="" KAFKA_PORT="" \
    run "$perl" -T ./check_kafka.pl -T "$KAFKA_TOPIC" -v

    run "$perl" -T ./check_kafka.pl -T "$KAFKA_TOPIC" -v

    run "$perl" -T ./check_kafka.pl -v

    run_conn_refused ./check_kafka.py -v

    echo "checking custom connection refused:"
    # Perl library error doesn't give a usual connection refused / failed to connect msg
    ERRCODE=2 run_grep "Cannot get metadata" "$perl" -T ./check_kafka.pl -v -P 9999

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Kafka tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

run_test_versions Kafka

if is_CI; then
    docker_image_cleanup
    echo
fi
