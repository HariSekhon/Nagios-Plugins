#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-12-18 16:55:07 +0000 (Sun, 18 Dec 2016)
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
#                                R a b b i t M Q
# ============================================================================ #
"

export RABBITMQ_VERSIONS="${@:-${RABBITMQ_VERSIONS:-management 3.4-management 3.5-management 3.6-management}}"

RABBITMQ_HOST="${DOCKER_HOST:-${RABBITMQ_HOST:-${HOST:-localhost}}}"
RABBITMQ_HOST="${RABBITMQ_HOST##*/}"
RABBITMQ_HOST="${RABBITMQ_HOST%%:*}"
export RABBITMQ_HOST

export RABBITMQ_PORT="${RABBITMQ_PORT:-5672}"

export RABBITMQ_USER="rabbitmq_user"
export RABBITMQ_PASSWORD="rabbitmq_password"

check_docker_available

# needs to be longer than 10 to allow RabbitMQ to settle so topic creation works
startupwait 20

test_rabbitmq(){
    local version="$1"
    echo "Setting up RabbitMQ $version test containers"
    hr
    #local DOCKER_OPTS=""
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $RABBITMQ_PORT
    VERSION="$version" docker-compose up -d
    rabbitmq_port="`docker-compose port "$DOCKER_SERVICE" "$RABBITMQ_PORT" | sed 's/.*://'`"
    local RABBITMQ_PORT="$rabbitmq_port"
    when_ports_available "$startupwait" "$RABBITMQ_HOST" "$RABBITMQ_PORT"
    # echo sleeping 30 secs
    #sleep 30
    hr
    #echo "creating RabbitMQ queue"
    #docker-compose exec "$DOCKER_SERVICE" rabbitmq-topics.sh --zookeeper localhost:2181 --create --replication-factor 1 --partitions 1 --topic "$RABBITMQ_TOPIC" || :
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    if [ "$version" = "latest" ]; then
        local version="*"
    fi
    hr
    set +e
    # -T often returns no output, just strip leading escape chars instead
    #found_version="$(docker-compose exec "$DOCKER_SERVICE" /bin/sh -c 'ls -d /rabbitmq_*' | tail -n1 | tr -d '$\r' | sed 's/.*\/rabbitmq_//; s/\.[[:digit:]]*\.[[:digit:]]*$//')"
    set -e
    #if [[ "${found_version//-/_}" != ${version//-/_}* ]]; then
    #    echo "Docker container version does not match expected version! (found '$found_version', expected '$version')"
    #    exit 1
    #fi
    hr
    set +e
    ./check_rabbitmq.py -u wronguser -p wrongpassword -v
    check_exit_code 2
    set -e
    hr
    ./check_rabbitmq.py -v
    hr
    #delete_container
    docker-compose down
    echo
}

for version in $(ci_sample $RABBITMQ_VERSIONS); do
    test_rabbitmq $version
done
