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

. ./tests/utils.sh

section "S o l r"

export SOLR_VERSIONS="${@:-${SOLR_VERSIONS:-latest 3.1 3.6 4.10 5.5 6.0 6.1 6.2 6.3 6.4 6.5 6.6}}"

SOLR_HOST="${DOCKER_HOST:-${SOLR_HOST:-${HOST:-localhost}}}"
SOLR_HOST="${SOLR_HOST##*/}"
SOLR_HOST="${SOLR_HOST%%:*}"
export SOLR_HOST
export SOLR_PORT_DEFAULT=8983
export SOLR_COLLECTION="${SOLR_COLLECTION:-test}"
export SOLR_CORE="${SOLR_COLLECTION:-${SOLR_CORE:-test}}"

export SOLR_HOME=/solr

startupwait 10

check_docker_available

trap_debug_env solr

test_solr(){
    local version="$1"
    section2 "Setting up Solr $version docker test container"
    VERSION="$version" docker-compose pull $docker_compose_quiet
    VERSION="$version" docker-compose up -d
    echo "getting Solr dynamic port mapping:"
    printf "getting Solr HTTP port => "
    export SOLR_PORT="`docker-compose port "$DOCKER_SERVICE" "$SOLR_PORT_DEFAULT" | sed 's/.*://'`"
    echo "$SOLR_PORT"
    hr
    when_ports_available $startupwait $SOLR_HOST $SOLR_PORT
    hr
    when_url_content "$startupwait" "http://$SOLR_HOST:$SOLR_PORT/solr/" "Solr Admin"
    hr
    if [[ "$version" = "latest" || ${version:0:1} > 3 ]]; then
        echo "attempting to create Solr Core"
        docker-compose exec "$DOCKER_SERVICE" solr create_core -c "$SOLR_CORE" || :
        # TODO: fix this on Solr 5.x+
        echo "attempting to create Solr Collection"
        docker-compose exec "$DOCKER_SERVICE" "$SOLR_HOME/bin/post" -c "$SOLR_CORE" "$SOLR_HOME/example/exampledocs/money.xml" || :
    fi
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    echo "Setup done, starting checks ..."
    if [[ "$version" = "latest" || ${version:0:1} > 3 ]]; then
        if [ "$version" = "latest" ]; then
            local version=".*"
        fi
        # 4.x+
        hr
        run ./check_solr_version.py -e "$version"
    else
        # TODO: check Solr v3 versions somehow
        :
    fi
    hr
    run_conn_refused ./check_solr_version.py -e "$version"
    hr
    run $perl -T ./check_solr_api_ping.pl -v -w 1000 -c 2000
    hr
    run_conn_refused $perl -T ./check_solr_api_ping.pl -v -w 1000 -c 2000
    hr
    run $perl -T ./check_solr_metrics.pl --cat CACHE -K queryResultCache -s cumulative_hits
    hr
    run_conn_refused $perl -T ./check_solr_metrics.pl --cat CACHE -K queryResultCache -s cumulative_hits
    hr
    run $perl -T ./check_solr_core.pl -v --index-size 100 --heap-size 100 --num-docs 10 -w 2000
    hr
    run_conn_refused $perl -T ./check_solr_core.pl -v --index-size 100 --heap-size 100 --num-docs 10 -w 2000
    hr
    num_expected_docs=4
    [ "${version:0:1}" -lt 4 ] && num_expected_docs=0
    # TODO: fix Solr 5 + 6 doc insertion and then tighten this up
    run $perl -T ./check_solr_query.pl -n 0:4 -w 200 -v
    hr
    run_conn_refused $perl -T ./check_solr_query.pl -n 0:4 -w 200 -v
    hr
    run $perl -T ./check_solr_write.pl -v -w 1000 # because Travis is slow
    hr
    run_conn_refused $perl -T ./check_solr_write.pl -v -w 1000
    hr
    echo "Completed $run_count Solr tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

run_test_versions Solr
