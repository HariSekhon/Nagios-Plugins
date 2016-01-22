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
#  http://www.linkedin.com/in/harisekhon
#

set -eu
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                           E l a s t i c s e a r c h
# ============================================================================ #
"

export ELASTICSEARCH_HOST="${ELASTICSEARCH_HOST:-localhost}"
export ELASTICSEARCH_PORT="${ELASTICSEARCH_PORT:-9200}"
export ELASTICSEARCH_INDEX="${ELASTICSEARCH_INDEX:-test}"
export DOCKER_CONTAINER="nagios-plugins-elasticsearch"

if ! which docker &>/dev/null; then
    echo 'WARNING: Docker not found, skipping Elasticsearch checks!!!'
fi

echo "Setting up test Elasticsearch container"
# reuse container it's faster
#docker rm -f "$DOCKER_CONTAINER" &>/dev/null
#sleep 1
if ! docker ps | tee /dev/stderr | grep -q "[[:space:]]$DOCKER_CONTAINER$"; then
    echo "Starting Docker Elasticsearch test container"
    docker run -d --name "$DOCKER_CONTAINER" -p 9200:9200 elasticsearch
    sleep 10
else
    echo "Docker Elasticsearch test container already running"
fi
# Travis added this
#echo "deleting twitter index as 5 unassigned shards are breaking tests"
#curl -XDELETE "http://localhost:9200/twitter" || :
#curl -XDELETE "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/$ELASTICSEARCH_INDEX" || :
# always returns 0 and I don't wanna parse the json error
#if ! curl -s "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/$ELASTICSEARCH_INDEX" &>/dev/null; then
if ! $perl -T $I_lib ./check_elasticsearch_index_exists.pl --list-indices | grep "^[[:space:]]*$ELASTICSEARCH_INDEX[[:space:]]*$"; then
    echo "creating test Elasticsearch index '$ELASTICSEARCH_INDEX'"
    curl -iv -XPUT "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/$ELASTICSEARCH_INDEX/" -d '
    {
        "settings": {
            "index": {
                "number_of_shards": 1,
                "number_of_replicas": 0
            }
        }
    }
    '
fi
echo
echo "Setup done, starting checks ..."
echo
hr
$perl -T $I_lib ./check_elasticsearch.pl -v
hr
# Listing checks return UNKNOWN
set +e
export ELASTICSEARCH_NODE="$($perl -T $I_lib ./check_elasticsearch_fielddata.pl --list-nodes | grep -v -e '^Nodes' -e '^Hostname' -e '^[[:space:]]*$' | head -n1 | awk '{print $1}' )"
echo "determined Elasticsearch node = $ELASTICSEARCH_NODE"
#result=$?
#[ $result = 3 ] || exit $result
hr
$perl -T $I_lib ./check_elasticsearch_index_exists.pl --list-indices
result=$?
[ $result = 3 ] || exit $result
set -e
hr
$perl -T $I_lib ./check_elasticsearch_cluster_disk_balance.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_cluster_shards.pl -v # --unassigned-shards 5,5 # travis now has 5 unassigned shards for some reason
hr
$perl -T $I_lib ./check_elasticsearch_cluster_shard_balance.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_cluster_stats.pl -v
hr
set +e
$perl -T $I_lib ./check_elasticsearch_cluster_status.pl -v
# travis has yellow status
result=$?
[ $result = 0 -o $result = 1 ] || exit $result
set -e
hr
$perl -T $I_lib ./check_elasticsearch_cluster_status_nodes_shards.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_data_nodes.pl -w 1 -v
hr
$perl -T $I_lib ./check_elasticsearch_doc_count.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_fielddata.pl -N "$ELASTICSEARCH_NODE" -v
hr
$perl -T $I_lib ./check_elasticsearch_index_exists.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_index_age.pl -v -w 0:1
#hr
#perl -T $I_lib ./check_elasticsearch_index_health.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_index_replicas.pl -w 0 -v
hr
$perl -T $I_lib ./check_elasticsearch_index_settings.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_index_shards.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_index_stats.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_master_node.pl -v
hr
$perl -T $I_lib ./check_elasticsearch_nodes.pl -v -w 1
hr
$perl -T $I_lib ./check_elasticsearch_node_disk_percent.pl -N "$ELASTICSEARCH_NODE" -v -w 90 -c 95
hr
$perl -T $I_lib ./check_elasticsearch_node_shards.pl -N "$ELASTICSEARCH_NODE" -v
hr
$perl -T $I_lib ./check_elasticsearch_node_stats.pl -N "$ELASTICSEARCH_NODE" -v
hr
$perl -T $I_lib ./check_elasticsearch_shards_state_detail.pl -v
hr
echo
echo -n "Deleting container "
docker rm -f "$DOCKER_CONTAINER"
echo; echo
