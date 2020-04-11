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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

test_mariadb_sh="test_mariadb.sh"

if [ "${0##*/}" = "$test_mariadb_sh" ]; then
    section "M a r i a D B"
else
    section "M y S Q L"
fi

export MYSQL_VERSIONS="${*:-${MYSQL_VERSIONS:-5.5 5.6 5.7 8.0 latest}}"
export MARIADB_VERSIONS="${*:-${MARIADB_VERSIONS:-5.5 10.1 10.2 10.3 latest}}"

MYSQL_HOST="${DOCKER_HOST:-${HOST:-localhost}}"
MYSQL_HOST="${MYSQL_HOST##*/}"
MYSQL_HOST="${MYSQL_HOST%%:*}"
# using 'localhost' causes mysql driver to try to shortcut to using local socket
# which doesn't work in Dockerized environment
[ "$MYSQL_HOST" = "localhost" ] && MYSQL_HOST="127.0.0.1"
export MYSQL_HOST

export MYSQL_DATABASE="${MYSQL_DATABASE:-mysql}"
export MYSQL_PORT_DEFAULT=3306
export HAPROXY_PORT_DEFAULT=3306
export MYSQL_USER="root"
export MYSQL_PASSWORD="test123"
export MYSQL_ROOT_PASSWORD="$MYSQL_PASSWORD"

#export MYSQL_CONFIG_PATH_DEFAULT=/etc/mysql/mysql.conf.d
#export MYSQL_CONFIG_FILE_DEFAULT=mysqld.cnf

check_docker_available

trap_debug_env mysql mariadb

startupwait 20

test_mysql(){
    test_db MySQL "$1"
}

test_mariadb(){
    test_db MariaDB "$1"
}

test_db(){
    local name="$1"
    local version="$2"
    name_lower="$(tr '[:upper:]' '[:lower:]' <<< "$name")"
    local export COMPOSE_FILE="$srcdir/docker/$name_lower-docker-compose.yml"
    section2 "Setting up $name $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting $name dynamic port mapping:"
    docker_compose_port MYSQL_PORT "$name"
    DOCKER_SERVICE=mysql-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$MYSQL_HOST" "$MYSQL_PORT" "$HAPROXY_PORT"
    hr
    # kind of an abuse of the protocol but good extra validation step
    when_url_content "http://$MYSQL_HOST:$MYSQL_PORT" "$name|$name_lower"
    hr
    echo "checking HAProxy MySQL:"
    when_url_content "http://$MYSQL_HOST:$MYSQL_PORT" "$name|$name_lower"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    # TODO: add mysql version test
    echo "finding my.cnf location"
    set +o pipefail
    MYSQL_CONFIG_FILE="my.cnf"
    my_cnf="$(docker exec -ti "$DOCKER_CONTAINER" find /etc -type f -name my.cnf -o -name mysqld.cnf | head -n1 | tr -d '\r')"
    set -o pipefail
    echo "determined my.cnf location to be $my_cnf"
    echo "fetching $my_cnf to local host:"
    # must require newer version of docker?
    #docker cp -L "$docker_container":"$MYSQL_CONFIG_PATH/$MYSQL_CONFIG_FILE" /tmp
    # doesn't let you specify a file path only dir otherwise gives annoying and inflexible error "not a directory"
    docker cp "$DOCKER_CONTAINER":"$my_cnf" "/tmp/"
    echo "copied to docker:$my_cnf => /tmp"
    if [ "/tmp/${my_cnf##*/}" != "/tmp/$MYSQL_CONFIG_FILE" ]; then
        mv -vf "/tmp/${my_cnf##*/}" "/tmp/$MYSQL_CONFIG_FILE"
    fi
    if docker cp "$DOCKER_CONTAINER":/etc/mysql/conf.d/ /tmp/; then
        echo "Found /etc/mysql/conf.d/, catting config to -> /tmp/$MYSQL_CONFIG_FILE"
        cat /tmp/conf.d/* >> "/tmp/$MYSQL_CONFIG_FILE"
    fi
    if docker cp "$DOCKER_CONTAINER":/etc/mysql/mysql.conf.d/ /tmp/; then
        echo "Found /etc/mysql/mysql.conf.d/, catting config to -> /tmp/$MYSQL_CONFIG_FILE"
        cat /tmp/mysql.conf.d/* >> "/tmp/$MYSQL_CONFIG_FILE"
    fi
    hr
    extra_opt=""
    if [ "$name" = "MariaDB" ]; then
        extra_opt="--ignore thread_cache_size"
        # for some reason MariaDB's thread_cache_size is 128 in conf vs 100 in running service in Docker, so ignore it
    fi

    mysql_tests

    echo
    section2 "Running HAProxy MySQL tests:"
    echo

    MYSQL_PORT="$HAPROXY_PORT" \
    mysql_tests

    rm -vf "/tmp/$MYSQL_CONFIG_FILE"
    hr

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count $name tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

mysql_tests(){
    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154,SC2086
    run "$perl" -T ./check_mysql_config.pl -c "/tmp/$MYSQL_CONFIG_FILE" --warn-on-missing -v $extra_opt

    # want splitting
    # shellcheck disable=SC2086
    run_conn_refused "$perl" -T ./check_mysql_config.pl -c "/tmp/$MYSQL_CONFIG_FILE" --warn-on-missing -v $extra_opt

    #echo "$perl -T ./check_mysql_query.pl -q \"SHOW TABLES IN information_schema like 'C%'\" -o CHARACTER_SETS -v"
    run "$perl" -T ./check_mysql_query.pl -q "SHOW TABLES IN information_schema like 'C%'" -o CHARACTER_SETS -v

    run "$perl" -T ./check_mysql_query.pl -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -r "'(root|mysql.sys)'@'(%|localhost)'" -v

    run_fail 2 "$perl" -T ./check_mysql_query.pl -q "SELECT FAILURE" -v

    echo "checking non SELECT / SHOW query triggers unknown usage result:"
    run_usage "$perl" -T ./check_mysql_query.pl -q "INVALID_QUERY" -v

    echo "checking invalid query hits MySQL error resulting in critical error:"
    run_fail 2 "$perl" -T ./check_mysql_query.pl -q "SHOW INVALID_QUERY" -v

    run_conn_refused "$perl" -T ./check_mysql_query.pl -q "SHOW TABLES IN information_schema like 'C%'" -o CHARACTER_SETS -v

    run_usage "$perl" -T ./check_mysql_query.pl -d mysql -q "DROP table haritest" -r 1 -v

    run_usage "$perl" -T ./check_mysql_query.pl -d mysql -q "DELETE FROM haritest where 1=1" -r 1 -v

    run_usage "$perl" -T ./check_mysql_query.pl -d mysql -q "SELECT * FROM (DROP TABLE haritest)" -r 1 -v

    run_usage "$perl" -T ./check_mysql_query.pl -d mysql -q "SELECT * FROM (DELETE FROM haritest where 1=1)" -r 1 -v

    # TODO: add socket test - must mount on a compiled system, ie replace the docker image with a custom test one
    # this breaks subsequent iterations of this function
    #unset MYSQL_HOST
    #$perl -T ./check_mysql_query.pl -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -o "'root'@'localhost'" -v
}

# This will get called twice in each of 2 separate Travis CI builds, once for MySQL and once for MariaDB, so skip one build in each to save time
if is_travis; then
    if [ $((RANDOM % 2)) = 0 ]; then
        echo "detected Travis CI, skipping build this time"
        exit 0
    fi
fi

if [ "${0##*/}" = "$test_mariadb_sh" ]; then
    run_test_versions MariaDB
else
    run_test_versions MySQL
fi

if is_CI; then
    docker_image_cleanup
    echo
fi
