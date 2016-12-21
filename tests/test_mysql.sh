#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
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

. ./tests/utils.sh

echo "
# ============================================================================ #
#                                   M y S Q L
# ============================================================================ #
"

export MYSQL_VERSIONS="${@:-${MYSQL_VERSIONS:-latest 5.5 5.6 5.7}}"

MYSQL_HOST="${MYSQL_HOST:-${DOCKER_HOST:-${HOST:-localhost}}}"
MYSQL_HOST="${MYSQL_HOST##*/}"
MYSQL_HOST="${MYSQL_HOST%%:*}"
# using 'localhost' causes mysql driver to try to shortcut to using local socket
# which doesn't work in Dockerized environment
[ "$MYSQL_HOST" = "localhost" ] && MYSQL_HOST="127.0.0.1"
export MYSQL_HOST

export MYSQL_DATABASE="${MYSQL_DATABASE:-mysql}"
export MYSQL_PORT=3306
export MYSQL_USER="root"
export MYSQL_PASSWORD="test123"
export MYSQL_ROOT_PASSWORD="$MYSQL_PASSWORD"

export MYSQL_CONFIG_PATH=/etc/mysql/mysql.conf.d
export MYSQL_CONFIG_FILE=mysqld.cnf

check_docker_available

startupwait 10

test_mysql(){
    local version="$1"
    echo "Setting up MySQL $version test container"
    #local DOCKER_OPTS="-e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $MYSQL_PORT
    VERSION="$version" docker-compose up -d
    mysql_port="`docker-compose port "$DOCKER_SERVICE" "$MYSQL_PORT" | sed 's/.*://'`"
    local MYSQL_PORT="$mysql_port"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available $startupwait $MYSQL_HOST $MYSQL_PORT
    hr
    local docker_container="$(docker-compose ps | sed -n '3s/ .*//p')"
    echo "determined docker container to be '$docker_container'"
    echo "fetching my.cnf to local host"
    docker cp "$docker_container":"$MYSQL_CONFIG_PATH/$MYSQL_CONFIG_FILE" /tmp
    $perl -T ./check_mysql_config.pl -c "/tmp/$MYSQL_CONFIG_FILE" --warn-on-missing -v
    rm -f "/tmp/$MYSQL_CONFIG_FILE"
    hr
    $perl -T ./check_mysql_query.pl -q "SHOW TABLES IN information_schema" -o CHARACTER_SETS -v
    hr
    #$perl -T ./check_mysql_query.pl -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -o "'root'@'localhost'" -v
    hr
    $perl -T ./check_mysql_query.pl -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -o "'root'@'%'" -v
    # TODO: add socket test - must mount on a compiled system, ie replace the docker image with a custom test one
    unset MYSQL_HOST
    #$perl -T ./check_mysql_query.pl -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -o "'root'@'localhost'" -v
    hr
    #delete_container
    docker-compose down
    hr
    echo
}

for version in $(ci_sample $MYSQL_VERSIONS); do
    test_mysql $version
done
