#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-22 21:13:49 +0000 (Fri, 22 Jan 2016)
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

section "S o l r"

export SOLR_VERSIONS="${*:-${SOLR_VERSIONS:-3.1 3.6 4.10 5.5 6.0 6.1 6.2 6.3 6.4 6.5 6.6 7.0 7.1 7.2 7.3 7.4 7.5 7.6 latest}}"

SOLR_HOST="${DOCKER_HOST:-${SOLR_HOST:-${HOST:-localhost}}}"
SOLR_HOST="${SOLR_HOST##*/}"
SOLR_HOST="${SOLR_HOST%%:*}"
export SOLR_HOST
export SOLR_PORT_DEFAULT=8983
export HAPROXY_PORT_DEFAULT=8983
export SOLR_COLLECTION="${SOLR_COLLECTION:-test}"
export SOLR_CORE="${SOLR_COLLECTION:-${SOLR_CORE:-test}}"

export SOLR_HOME=/solr

startupwait 10

check_docker_available

trap_debug_env solr

test_solr(){
    local version="$1"
    section2 "Setting up Solr $version docker test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    echo "getting Solr dynamic port mapping:"
    docker_compose_port SOLR_PORT "Solr HTTP"
    DOCKER_SERVICE=solr-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$SOLR_HOST" "$SOLR_PORT"
    hr
    when_url_content "http://$SOLR_HOST:$SOLR_PORT/solr/" "Solr Admin"
    hr
    echo "checking HAProxy Solr:"
    when_url_content "http://$SOLR_HOST:$HAPROXY_PORT/solr/" "Solr Admin"
    hr
    if [ "$version" != "3.1" ] &&
       [ -z "${NOSETUP:-}" ]; then
        echo "attempting to create Solr Core"
        # excluding from 3.1 test due to following error:
        # rpc error: code = 2 desc = oci runtime error: exec failed: container_linux.go:247: starting container process caused "exec: \"solr\": executable file not found in $PATH"
        docker-compose exec "$DOCKER_SERVICE" solr create_core -c "$SOLR_CORE" || :
        hr
        echo "attempting to create Solr Collection"
        docker-compose exec "$DOCKER_SERVICE" "$SOLR_HOME/bin/post" -c "$SOLR_CORE" "$SOLR_HOME/example/exampledocs/money.xml" || :
        echo "Setup done"
        hr
    fi
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi

    solr_tests

    solr_conn_refused_tests

    echo
    section2 "HAProxy Solr tests:"
    echo

    SOLR_PORT="$HAPROXY_PORT" \
    solr_tests

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Solr tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

solr_tests(){
    if [ "${version:0:1}" != "3" ]; then
        if [ "$version" = "latest" ]; then
            local version
            version="$(dockerhub_latest_version solr)"
        fi
        # 4.x+
        run ./check_solr_version.py -e "$version"

        run_fail 2 ./check_solr_version.py -e "fail-version"
    else
        docker_compose_version_test solr "$version"
        hr
    fi

    # not available in Solr 3.x and collection not loaded in 4.10 above due to lack of bin/post command
    if ! [[ "$version" =~ ^3|^4 ]]; then
        # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
        # shellcheck disable=SC2154
        run "$perl" -T ./check_solr_api_ping.pl -v -w 1000 -c 2000
    fi

    # core / collection not created above in versions < 5
    if ! [[ "$version" =~ ^3|^4 ]]; then
        run "$perl" -T ./check_solr_core.pl -v --index-size 100 --heap-size 100 --num-docs 10 -w 2000
    fi

    if ! [[ "$version" =~ ^3|^4 ]]; then
        run "$perl" -T ./check_solr_metrics.pl --cat CACHE -K queryResultCache -s cumulative_hits

        # several categories return no metrics at this point
        for category in $(./check_solr_metrics.pl --list-categories | tail -n +3 | grep -Ev -e 'CONTAINER|QUERYPARSER|SPELLCHECKER|SEARCHER|TLOG|INDEX|DIRECTORY|HTTP|OTHER'); do
            run "$perl" -T ./check_solr_metrics.pl --category "$category"
        done
    fi

    num_expected_docs=5
    # docs are not loaded in 3.1 test
    [ "$version" = "3.1" ] && num_expected_docs=0
    # core / collection not created above in versions < 5
    if ! [[ "$version" =~ ^3|^4 ]]; then
        run "$perl" -T ./check_solr_query.pl -n 0:$num_expected_docs -w 200 -v

        run "$perl" -T ./check_solr_write.pl -v -w 1000 # because Travis is slow
    fi

}

solr_conn_refused_tests(){
    run_conn_refused ./check_solr_version.py -e "$version"
    run_conn_refused "$perl" -T ./check_solr_api_ping.pl -v -w 1000 -c 2000
    run_conn_refused "$perl" -T ./check_solr_core.pl -v --index-size 100 --heap-size 100 --num-docs 10 -w 2000
    run_conn_refused "$perl" -T ./check_solr_metrics.pl --cat CACHE -K queryResultCache -s cumulative_hits
    run_conn_refused "$perl" -T ./check_solr_query.pl -n 0:$num_expected_docs -w 200 -v
    run_conn_refused "$perl" -T ./check_solr_write.pl -v -w 1000
}

run_test_versions Solr

if is_CI; then
    docker_image_cleanup
    echo
fi
