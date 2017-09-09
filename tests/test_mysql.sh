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

if [ ${0##*/} = "test_mariadb.sh" ]; then
    section "M a r i a D B"
else
    section "M y S Q L"
fi

export MYSQL_VERSIONS="${@:-${MYSQL_VERSIONS:-latest 5.5 5.6 5.7 8.0}}"
export MARIADB_VERSIONS="${@:-${MYSQL_VERSIONS:-latest 5.5 10.1 10.2 10.3}}"

MYSQL_HOST="${MYSQL_HOST:-${DOCKER_HOST:-${HOST:-localhost}}}"
MYSQL_HOST="${MYSQL_HOST##*/}"
MYSQL_HOST="${MYSQL_HOST%%:*}"
# using 'localhost' causes mysql driver to try to shortcut to using local socket
# which doesn't work in Dockerized environment
[ "$MYSQL_HOST" = "localhost" ] && MYSQL_HOST="127.0.0.1"
export MYSQL_HOST

export MYSQL_DATABASE="${MYSQL_DATABASE:-mysql}"
export MYSQL_PORT_DEFAULT=3306
export MYSQL_USER="root"
export MYSQL_PASSWORD="test123"
export MYSQL_ROOT_PASSWORD="$MYSQL_PASSWORD"

#export MYSQL_CONFIG_PATH_DEFAULT=/etc/mysql/mysql.conf.d
#export MYSQL_CONFIG_FILE_DEFAULT=mysqld.cnf

check_docker_available

trap_debug_env mysql mariadb

startupwait 10

test_mysql(){
    test_db MySQL "$1"
}

test_mariadb(){
    test_db MariaDB "$1"
}

test_db(){
    local name="$1"
    local version="$2"
    local export DOCKER_SERVICE="$(tr 'A-Z' 'a-z' <<< "$name")"
    local export COMPOSE_FILE="$srcdir/docker/$DOCKER_SERVICE-docker-compose.yml"
    echo "Setting up $name $version test container"
    #local DOCKER_OPTS="-e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $MYSQL_PORT
    VERSION="$version" docker-compose up -d
    echo "Getting $name port mapping"
    echo -n "MySQL port => "
    export MYSQL_PORT="`docker-compose port "$DOCKER_SERVICE" "$MYSQL_PORT_DEFAULT" | sed 's/.*://'`"
    if [ "$version" = "latest" -o "${version%%.*}" -gt 5 ]; then
        export MYSQL_CONFIG_PATH="/etc/mysql/mysql.conf.d"
        export MYSQL_CONFIG_FILE="mysqld.cnf"
    else
        export MYSQL_CONFIG_PATH="/etc/mysql"
        export MYSQL_CONFIG_FILE="my.cnf"
    fi
    echo "$MYSQL_PORT"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available $startupwait $MYSQL_HOST $MYSQL_PORT
    hr
    local docker_container="$(docker-compose ps | sed -n '3s/ .*//p')"
    echo "determined docker container to be '$docker_container'"
    echo "fetching my.cnf to local host"
    docker cp "$docker_container":"$MYSQL_CONFIG_PATH/$MYSQL_CONFIG_FILE" /tmp
    hr
    extra_opt=""
    if [ "$name" = "MariaDB" ]; then
        extra_opt="--ignore thread_cache_size"
        # for some reason MariaDB's thread_cache_size is 128 in conf vs 100 in running service in Docker, so ignore it
    fi
    echo "$perl -T ./check_mysql_config.pl -c \"/tmp/$MYSQL_CONFIG_FILE\" --warn-on-missing -v $extra_opt"
    $perl -T ./check_mysql_config.pl -c "/tmp/$MYSQL_CONFIG_FILE" --warn-on-missing -v $extra_opt
    rm -vf "/tmp/$MYSQL_CONFIG_FILE"
    hr
    echo "$perl -T ./check_mysql_query.pl -q \"SHOW TABLES IN information_schema like 'C%'\" -o CHARACTER_SETS -v"
    $perl -T ./check_mysql_query.pl -q "SHOW TABLES IN information_schema like 'C%'" -o CHARACTER_SETS -v
    hr
    echo "$perl -T ./check_mysql_query.pl -d information_schema -q \"SELECT * FROM user_privileges LIMIT 1\"  -r \"'(root|mysql.sys)'@'(%|localhost)'\" -v"
    $perl -T ./check_mysql_query.pl -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -r "'(root|mysql.sys)'@'(%|localhost)'" -v
    # TODO: add socket test - must mount on a compiled system, ie replace the docker image with a custom test one
    unset MYSQL_HOST
    #$perl -T ./check_mysql_query.pl -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -o "'root'@'localhost'" -v
    hr
    #delete_container
    docker-compose down
    hr
    echo
}

if [ ${0##*/} = "test_mariadb.sh" ]; then
    run_test_versions MariaDB
else
    run_test_versions MySQL
fi
