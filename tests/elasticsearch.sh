#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-05-25 01:38:24 +0100 (Mon, 25 May 2015)
#
#  https://github.com/harisekhon
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

. tests/travis.sh

echo "
# ============================================================================ #
#                           E l a s t i c s e a r c h
# ============================================================================ #
"

export ELASTICSEARCH_HOST="${ELASTICSEARCH_HOST:-localhost}"
export ELASTICSEARCH_INDEX="${ELASTICSEARCH_INDEX:-test}"

echo "creating test Elasticsearch index '$ELASTICSEARCH_INDEX'"
curl -XPUT "http://localhost:9200/$ELASTICSEARCH_INDEX/" -d '
{
    "settings": {
        "index": {
            "number_of_shards": 1,
            "number_of_replicas": 0
        }
    }
}
'
echo
echo done
hr
perl -T $I_lib ./check_elasticsearch.pl -v
hr
# Listing checks return UNKNOWN, so reset their exit code to zero
perl -T $I_lib ./check_elasticsearch_fielddata.pl --list-nodes || :
hr
perl -T $I_lib ./check_elasticsearch_index_exists.pl --list-indices || :
hr
perl -T $I_lib ./check_elasticsearch_cluster_disk_balance.pl -v
hr
perl -T $I_lib ./check_elasticsearch_cluster_shards.pl -v
hr
perl -T $I_lib ./check_elasticsearch_cluster_shard_balance.pl -v
hr
perl -T $I_lib ./check_elasticsearch_cluster_stats.pl -v
hr
perl -T $I_lib ./check_elasticsearch_cluster_status.pl -v
hr
perl -T $I_lib ./check_elasticsearch_cluster_status_nodes_shards.pl -v
hr
perl -T $I_lib ./check_elasticsearch_data_nodes.pl -w 1 -v
hr
perl -T $I_lib ./check_elasticsearch_doc_count.pl -v
hr
perl -T $I_lib ./check_elasticsearch_fielddata.pl -N 127.0.0.1 -v
hr
perl -T $I_lib ./check_elasticsearch_index_exists.pl -v
hr
perl -T $I_lib ./check_elasticsearch_index_age.pl -v -w 0:1
#hr
#perl -T $I_lib ./check_elasticsearch_index_health.pl -v
hr
perl -T $I_lib ./check_elasticsearch_index_replicas.pl -w 0 -v
hr
perl -T $I_lib ./check_elasticsearch_index_settings.pl -v
hr
perl -T $I_lib ./check_elasticsearch_index_shards.pl -v
hr
perl -T $I_lib ./check_elasticsearch_index_stats.pl -v
hr
perl -T $I_lib ./check_elasticsearch_master_node.pl -v
hr
perl -T $I_lib ./check_elasticsearch_nodes.pl -v -w 1
hr
perl -T $I_lib ./check_elasticsearch_node_disk_percent.pl -N 127.0.0.1 -v
hr
perl -T $I_lib ./check_elasticsearch_node_shards.pl -N 127.0.0.1 -v
hr
perl -T $I_lib ./check_elasticsearch_node_stats.pl -N 127.0.0.1 -v
hr
perl -T $I_lib ./check_elasticsearch_shards_state_detail.pl -v

echo; echo
