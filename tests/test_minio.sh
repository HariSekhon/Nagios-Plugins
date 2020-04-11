#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-09-28 19:05:36 +0100 (Fri, 28 Sep 2018)
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

section "M i n i o"

export MINIO_VERSIONS="${*:-${MINIO_VERSIONS:-latest}}"

AWS_HOST="${DOCKER_HOST:-${AWS_HOST:-${HOST:-localhost}}}"
AWS_HOST="${AWS_HOST##*/}"
AWS_HOST="${AWS_HOST%%:*}"
export AWS_HOST
export MINIO_HOST="$AWS_HOST"
export MINIO_PORT_DEFAULT=9000
export HAPROXY_PORT_DEFAULT=9000

export AWS_ACCESS_KEY=MYMINIOACCESSKEY1234
export AWS_SECRET_KEY=MyMinioSecretKey1234MyMinioSecretKey1234

export MNTDIR="/pl"

check_docker_available

trap_debug_env minio aws

startupwait 20

test_minio(){
    local version="$1"
    section2 "Setting up Minio $version test container"
    docker_compose_pull
    # protects against using a stale ZooKeeper storage plugin config from a higher version which will result in an error as see in MINIO-4383
    #docker-compose down
    MINIO_ACCESS_KEY=$AWS_ACCESS_KEY MINIO_SECRET_KEY=$AWS_SECRET_KEY \
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Minio dynamic port mappings:"
    docker_compose_port "Minio"
    DOCKER_SERVICE=minio-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$MINIO_HOST" "$MINIO_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$MINIO_HOST:$MINIO_PORT/minio/login" "minio"
    hr
    echo "checking HAProxy Minio:"
    when_url_content "http://$MINIO_HOST:$HAPROXY_PORT/minio/login" "minio"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    minio_tests
    echo
    hr
    echo
    section2 "Running Minio HAProxy tests"
    MINIO_PORT="$HAPROXY_PORT" \
    minio_tests

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Minio tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    echo
}

minio_tests(){
    export AWS_PORT="$MINIO_PORT"
    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    run "$perl" -T check_aws_s3_file.pl -b bucket1 -f minio.txt --no-ssl

    run "$perl" -T check_aws_s3_file.pl -b bucket1 -f minio.txt --no-ssl --get

    echo "check fails if using SSL against Minio:"
    run_fail 2 "$perl" -T check_aws_s3_file.pl -b bucket1 -f minio.txt

    run_conn_refused "$perl" -T ./check_aws_s3_file.pl -b bucket1 -f minio.txt --no-ssl

    run_usage "$perl" -T check_aws_s3_file.pl -b bucket.1 -f minio.txt
    run_usage "$perl" -T check_aws_s3_file.pl -b bucket1
    run_usage "$perl" -T check_aws_s3_file.pl -f minio.txt
    run_usage "$perl" -T check_aws_s3_file.pl
}

run_test_versions "Minio"

if is_CI; then
    docker_image_cleanup
    echo
fi
