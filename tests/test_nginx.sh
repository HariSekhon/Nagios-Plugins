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
srcdir2="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir2/..";

. ./tests/utils.sh

# because including bash-tools/util.sh resets the srcdir
srcdir="$srcdir2"

section "N g i n x"

export NGINX_VERSIONS="${@:-${NGINX_VERSIONS:-latest 1.10 1.11.0}}"

NGINX_HOST="${DOCKER_HOST:-${NGINX_HOST:-${HOST:-localhost}}}"
NGINX_HOST="${NGINX_HOST##*/}"
NGINX_HOST="${NGINX_HOST%%:*}"
export NGINX_HOST

export NGINX_PORT_DEFAULT="80"

startupwait 5

check_docker_available

trap_debug_env nginx

test_nginx(){
    local version="$1"
    section2 "Setting up Nginx $version test container"
    # docker-compose up to create docker_default network, otherwise just doing create and then start results in error:
    # ERROR: for nginx  Cannot start service nginx: network docker_default not found
    # ensure we start fresh otherwise the first nginx stats stub failure test will fail as it finds the old stub config
    VERSION="$version" docker-compose down || :
    if is_CI; then
        VERSION="$version" docker-compose pull $docker_compose_quiet
    fi
    VERSION="$version" docker-compose up -d
    # Configure Nginx stats stub so watch_nginx_stats.pl now passes
    VERSION="$version" docker-compose stop
    echo "Now reconfiguring Nginx to support stats and restarting:"
    docker cp "$srcdir/conf/nginx/conf.d/default.conf" "$DOCKER_CONTAINER":/etc/nginx/conf.d/default.conf
    VERSION="$version" docker-compose start
    echo "getting Nginx dynamic port mapping:"
    docker_compose_port Nginx
    hr
    when_ports_available "$NGINX_HOST" "$NGINX_PORT"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    run ./check_nginx_version.py -e "$version"
    hr
    run_fail 2 ./check_nginx_version.py -e "fail-version"
    hr
    run_conn_refused ./check_nginx_version.py -e "$version"
    hr
    run $perl -T ./check_nginx_stats.pl -u /status
    hr
    run_fail 2 $perl -T ./check_nginx_stats.pl -u /nonexistent
    hr
    run_conn_refused $perl -T ./check_nginx_stats.pl -u /status
    hr
    echo "Completed $run_count Nginx tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

run_test_versions Nginx
