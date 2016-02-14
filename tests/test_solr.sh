#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-22 21:13:49 +0000 (Fri, 22 Jan 2016)
#
#  https://github.com/harisekhon
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
#                       S o l r   /   S o l r C l o u d
# ============================================================================ #
"

export SOLR_HOST="${SOLR_HOST:-${HOST:-localhost}}"
export SOLR_PORT="${SOLR_PORT:-8983}"
export SOLR_COLLECTION="${SOLR_COLLECTION:-test}"
export SOLR_CORE="${SOLR_COLLECTION:-${SOLR_CORE:-test}}"
export DOCKER_CONTAINER="nagios-plugins-solr"

if ! which docker &>/dev/null; then
    echo 'WARNING: Docker not found, skipping Solr checks!!!'
    exit 0
fi

echo "Setting up test Solr docker container"
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    docker rm -f "$DOCKER_CONTAINER" &>/dev/null || :
    echo "Starting Docker Solr test container"
    docker run -d --name "$DOCKER_CONTAINER" -p 8983:8983 solr
    echo "waiting 5 seconds for Solr to start up"
    sleep 5
    docker exec -it --user=solr "$DOCKER_CONTAINER" bin/solr create_core -c "$SOLR_CORE"
    docker exec -it --user=solr "$DOCKER_CONTAINER" bin/post -c "$SOLR_CORE" example/exampledocs/money.xml
else
    echo "Docker Solr test container already running"
fi
sleep 1

echo
echo "Setup done, starting checks ..."

hr
$perl -T $I_lib ./check_solr_api_ping.pl -v
hr
$perl -T $I_lib ./check_solr_metrics.pl --cat CACHE -K queryResultCache -s cumulative_hits
hr
$perl -T $I_lib ./check_solr_core.pl -v --index-size 100 --heap-size 100 --num-docs 10 -w 2000
hr
$perl -T $I_lib ./check_solr_query.pl -n 4 -v
hr
$perl -T $I_lib ./check_solr_write.pl -vvv 
# TODO: docker exec this to be a SolrCloud
#docker exec -it --user=solr "$DOCKER_CONTAINER" bin/solr delete_core -c "$SOLR_CORE"
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
