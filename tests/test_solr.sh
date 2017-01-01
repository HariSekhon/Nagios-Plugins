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

echo "
# ============================================================================ #
#                                    S o l r
# ============================================================================ #
"

export SOLR_VERSIONS="${@:-${SOLR_VERSIONS:-latest 3.1 3.6 4.10 5.5 6.0 6.1 6.2}}"

SOLR_HOST="${DOCKER_HOST:-${SOLR_HOST:-${HOST:-localhost}}}"
SOLR_HOST="${SOLR_HOST##*/}"
SOLR_HOST="${SOLR_HOST%%:*}"
export SOLR_HOST
export SOLR_PORT="${SOLR_PORT:-8983}"
export SOLR_COLLECTION="${SOLR_COLLECTION:-test}"
export SOLR_CORE="${SOLR_COLLECTION:-${SOLR_CORE:-test}}"

export SOLR_HOME=/solr

startupwait 10

check_docker_available

test_solr(){
    local version="$1"
    echo "Setting up Solr $version docker test container"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $SOLR_PORT
    VERSION="$version" docker-compose up -d
    solr_port="`docker-compose port "$DOCKER_SERVICE" "$SOLR_PORT" | sed 's/.*://'`"
    local SOLR_PORT="$solr_port"
    when_ports_available $startupwait $SOLR_HOST $SOLR_PORT
    if [[ "$version" = "latest" || ${version:0:1} > 3 ]]; then
        docker-compose exec "$DOCKER_SERVICE" solr create_core -c "$SOLR_CORE" || :
        # TODO: fix this on Solr 5.x+
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
        ./check_solr_version.py -e "$version"
    else
        # TODO: check Solr v3 versions somehow
        :
    fi
    hr
    $perl -T ./check_solr_api_ping.pl -v -w 1000 -c 2000
    hr
    $perl -T ./check_solr_metrics.pl --cat CACHE -K queryResultCache -s cumulative_hits
    hr
    $perl -T ./check_solr_core.pl -v --index-size 100 --heap-size 100 --num-docs 10 -w 2000
    hr
    num_expected_docs=4
    [ "${version:0:1}" -lt 4 ] && num_expected_docs=0
    # TODO: fix Solr 5 + 6 doc insertion and then tighten this up
    $perl -T ./check_solr_query.pl -n 0:4 -w 200 -v
    hr
    $perl -T ./check_solr_write.pl -v -w 1000 # because Travis is slow
    hr
    #delete_container
    docker-compose down
    hr
    echo
}

for version in $(ci_sample $SOLR_VERSIONS); do
    test_solr $version
done
