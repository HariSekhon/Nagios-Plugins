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
srcdir2="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir2/.."

. ./tests/utils.sh

srcdir="$srcdir2"

echo "
# ============================================================================ #
#                               S o l r C l o u d
# ============================================================================ #
"

SOLR_HOST="${DOCKER_HOST:-${SOLR_HOST:-${HOST:-localhost}}}"
SOLR_HOST="${SOLR_HOST##*/}"
export SOLR_HOST="${SOLR_HOST%%:*}"
export ZOOKEEPER_HOST="$SOLR_HOST"

export DOCKER_IMAGE="harisekhon/solrcloud-dev:4.10"
export DOCKER_CONTAINER="nagios-plugins-solrcloud-test"

export MNTDIR="/pl"

export SOLR_COLLECTION="collection1"

startupwait=60

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Hadoop checks!!!'
    exit 0
fi

docker_exec(){
    docker exec -ti "$DOCKER_CONTAINER" $MNTDIR/$@
}

echo "Setting up SolrCloud docker test container"
DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" 8983 8984 9983

hr
# docker is running slow
$perl -T $I_lib ./check_solrcloud_cluster_status.pl -v -t 60
hr
docker_exec check_solrcloud_cluster_status_zookeeper.pl -H localhost -P 9983 -b / -v
hr
# FIXME: doesn't pick up collection from env
docker_exec check_solrcloud_config_zookeeper.pl -H localhost -P 9983 -b / -C collection1 -d /solr/node1/solr/collection1/conf -v
hr
# FIXME: why is only 1 node up instead of 2
$perl -T $I_lib ./check_solrcloud_live_nodes.pl -w 1 -c 1 -t 60 -v
hr
docker_exec check_solrcloud_live_nodes_zookeeper.pl -H localhost -P 9983 -b / -w 1 -c 1 -v
hr
# docker is running slow
$perl -T $I_lib ./check_solrcloud_overseer.pl -t 60 -v
hr
docker_exec check_solrcloud_overseer_zookeeper.pl -H localhost -P 9983 -b / -v
hr
docker_exec check_solrcloud_server_znode.pl -H localhost -P 9983 -z /live_nodes/$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$DOCKER_CONTAINER"):8983_solr -v
hr
# FIXME: second node not up
#docker_exec check_solrcloud_server_znode.pl -H localhost -P 9983 -z /live_nodes/$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$DOCKER_CONTAINER"):8984_solr -v
hr
docker_exec check_zookeeper_config.pl -H localhost -P 9983 -C /solr/node1/solr/zoo.cfg --no-warn-extra -v
hr
delete_container
