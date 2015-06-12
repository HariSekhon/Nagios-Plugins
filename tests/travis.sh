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

export PERLBREW_ROOT="${PERLBREW_ROOT:-~/perl5/perlbrew}"

export TRAVIS_PERL_VERSION="${TRAVIS_PERL_VERSION:-*}"

# For Travis CI which installs modules locally
export PERL5LIB=$(echo \
    ${PERL5LIB:-.} \
    $PERLBREW_ROOT/perls/$TRAVIS_PERL_VERSION/lib/site_perl/$TRAVIS_PERL_VERSION.*/x86_64-linux \
    $PERLBREW_ROOT/perls/$TRAVIS_PERL_VERSION/lib/site_perl/$TRAVIS_PERL_VERSION.* \
    $PERLBREW_ROOT/perls/$TRAVIS_PERL_VERSION/lib/$TRAVIS_PERL_VERSION.*/x86_64-linux \
    $PERLBREW_ROOT/perls/$TRAVIS_PERL_VERSION/lib/$TRAVIS_PERL_VERSION.* \
    | tr '\n' ':'
)
# Taint code doesn't use PERL5LIB, use -I instead
I_lib=""
for x in $(echo "$PERL5LIB" | tr ':' ' '); do
    I_lib+="-I $x "
done

hr(){
    echo "===================="
}

echo "
# ============================================================================ #
#                               C a s s a n d r a
# ============================================================================ #
"

# Cassandra build in Travis is quite broken, appears due to an incorrect upgrade in the VM image

# workarounds for nodetool "You must set the CASSANDRA_CONF and CLASSPATH vars"
# even bare 'nodetool status' has broken environment in Travis, nothing to do with say Taint security
# Cassandra service on Travis is really broken, some hacks to make it work
if [ -n "$TRAVIS" ]; then
    export CASSANDRA_HOME="${CASSANDRA_HOME:-/usr/local/cassandra}"
    # these were only necessary on the debug VM but not in the actual Travis env for some reason
    #sudo sed -ibak 's/jamm-0.2.5.jar/jamm-0.2.8.jar/' $CASSANDRA_HOME/bin/cassandra.in.sh $CASSANDRA_HOME/conf/cassandra-env.sh
    #sudo sed -ribak 's/^(multithreaded_compaction|memtable_flush_queue_size|preheat_kernel_page_cache|compaction_preheat_key_cache|in_memory_compaction_limit_in_mb):.*//' $CASSANDRA_HOME/conf/cassandra.yaml
    # stop printing xss = $JAVA_OPTS which will break nodetool parsing
    sudo sed -ibak2 's/^echo "xss = .*//' $CASSANDRA_HOME/conf/cassandra-env.sh
    sudo service cassandra status || sudo service cassandra start
fi

# /usr/local/bin/nodetool symlink doesn't source cassandra.in.sh properly
#nodetool status
/usr/local/cassandra/bin/nodetool status
# Cassandra checks are broken due to broken nodetool environment
# must set full path to /usr/local/cassandra/bin/nodetool to bypass /usr/local/bin/nodetool symlink which doesn't source cassandra.in.sh properly and breaks with "You must set the CASSANDRA_CONF and CLASSPATH vars@
set +e
perl -T $I_lib ./check_cassandra_balance.pl  -n /usr/local/cassandra/bin/nodetool
hr
perl -T $I_lib ./check_cassandra_heap.pl     -n /usr/local/cassandra/bin/nodetool
hr
perl -T $I_lib ./check_cassandra_netstats.pl -n /usr/local/cassandra/bin/nodetool
hr
perl -T $I_lib ./check_cassandra_tpstats.pl  -n /usr/local/cassandra/bin/nodetool
set -e

echo; echo

echo "
# ============================================================================ #
#                           E l a s t i c s e a r c h
# ============================================================================ #
"

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
# ELASTICSEARCH_HOST, ELASTICSEARCH_INDEX obtained via .travis.yml
perl -T $I_lib ./check_elasticsearch.pl -v
hr
# Listing checks return UNKNOWN, so reset their exit code to zero
perl -T $I_lib ./check_elasticsearch_fielddata.pl --list-nodes || :
hr
perl -T $I_lib ./check_elasticsearch_index_exists.pl --list-indices || :
hr
perl -T $I_lib ./check_elasticsearch_cluster_shards.pl
hr
perl -T $I_lib ./check_elasticsearch_cluster_status.pl
hr
perl -T $I_lib ./check_elasticsearch_cluster_status_nodes_shards.pl
hr
perl -T $I_lib ./check_elasticsearch_data_nodes.pl -w 1 -v
hr
perl -T $I_lib ./check_elasticsearch_fielddata.pl -N 127.0.0.1
hr
perl -T $I_lib ./check_elasticsearch_index_exists.pl
#hr
#perl -T $I_lib ./check_elasticsearch_index_health.pl
hr
perl -T $I_lib ./check_elasticsearch_index_replicas.pl -w 0 -v
hr
perl -T $I_lib ./check_elasticsearch_index_settings.pl
hr
perl -T $I_lib ./check_elasticsearch_index_shards.pl
hr
perl -T $I_lib ./check_elasticsearch_index_stats.pl
hr
perl -T $I_lib ./check_elasticsearch_master_node.pl
hr
perl -T $I_lib ./check_elasticsearch_nodes.pl -w 1 -v
#hr
#perl -T $I_lib ./check_elasticsearch_node_stats.pl
hr
perl -T $I_lib ./check_elasticsearch_shards_detail.pl

echo; echo

echo "
# ============================================================================ #
#                               M e m c a c h e d
# ============================================================================ #
"

echo "creating test Memcached key-value"
echo -ne "add myKey 0 100 4\r\nhari\r\n" | nc localhost 11211
echo done
hr
# MEMCACHED_HOST obtained via .travis.yml
perl -T $I_lib ./check_memcached_write.pl
hr
perl -T $I_lib ./check_memcached_key.pl -k myKey -e hari
hr
perl -T $I_lib ./check_memcached_stats.pl -w 15 -c 20 -v

echo; echo

echo "
# ============================================================================ #
#                                M o n g o D B
# ============================================================================ #
"

# MONGODB_HOST obtained via .travis.yml
# not part of a replica set so this fails
#perl -T $I_lib ./check_mongodb_master.pl
#hr
#perl -T $I_lib ./check_mongodb_master_rest.pl
#hr
# Type::Tiny::XS currently doesn't build on Perl 5.8 due to a bug
if [ "$TRAVIS_PERL_VERSION" != "5.8" ]; then
    perl -T $I_lib ./check_mongodb_write.pl
fi

echo; echo

echo "
# ============================================================================ #
#                                   M y S Q L
# ============================================================================ #
"

# MYSQL_HOST, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD obtained via .travis.yml
perl -T $I_lib ./check_mysql_config.pl --warn-on-missing
hr
perl -T $I_lib ./check_mysql_query.pl -q "show tables in information_schema" -o CHARACTER_SETS

echo; echo

echo "
# ============================================================================ #
#                                   N e o 4 J
# ============================================================================ #
"

echo "creating test Neo4J node"
neo4j-shell -c 'CREATE (p:Person { name: "Hari Sekhon" })'
echo done
hr
# NEO4J_HOST obtained via .travis.yml
perl -T $I_lib ./check_neo4j_readonly.pl
hr
perl -T $I_lib ./check_neo4j_remote_shell_enabled.pl
hr
perl -T $I_lib ./check_neo4j_stats.pl
hr
perl -T $I_lib ./check_neo4j_stats.pl -s NumberOfNodeIdsInUse -c 1:1 -v
hr
# Neo4J on Travis doesn't seem to return anything resulting in "'attributes' field not returned by Neo4J" error
#perl -T $I_lib ./check_neo4j_store_sizes.pl -vvv
#hr
perl -T $I_lib ./check_neo4j_version.pl

echo; echo

echo "
# ============================================================================ #
#                                   R e d i s
# ============================================================================ #
"

echo "creating test Redis key-value"
echo set myKey hari | redis-cli
echo done
hr
# REDIS_HOST obtained via .travis.yml
perl -T $I_lib ./check_redis_clients.pl
hr
perl -T $I_lib ./check_redis_config.pl --no-warn-extra
hr
perl -T $I_lib ./check_redis_key.pl -k myKey -e hari
hr
perl -T $I_lib ./check_redis_publish_subscribe.pl
hr
perl -T $I_lib ./check_redis_stats.pl
hr
perl -T $I_lib ./check_redis_stats.pl -s connected_clients -c 1:1 -v
hr
perl -T $I_lib ./check_redis_version.pl
hr
perl -T $I_lib ./check_redis_write.pl

echo; echo

echo "
# ============================================================================ #
#                                   R I A K
# ============================================================================ #
"

echo "creating myBucket with n_val setting of 1 (to avoid warnings in riak-admin)"
sudo riak-admin bucket-type create myBucket '{"props":{"n_val":1}}'
echo "creating test Riak document"
# don't use new bucket types yet
#curl -XPUT localhost:8098/types/myType/buckets/myBucket/keys/myKey -d 'hari'
curl -XPUT localhost:8098/buckets/myBucket/keys/myKey -d 'hari'
echo "done"
hr
# RIAK_HOST obtained via .travis.yml
# needs sudo - uses wrong version of perl if not explicit path with sudo
sudo /home/travis/perl5/perlbrew/perls/$TRAVIS_PERL_VERSION/bin/perl -T $I_lib ./check_riak_diag.pl -vvv || :
hr
perl -T $I_lib ./check_riak_key.pl -b myBucket -k myKey -e hari
hr
# needs sudo
sudo /home/travis/perl5/perlbrew/perls/$TRAVIS_PERL_VERSION/bin/perl -T $I_lib ./check_riak_ringready.pl
hr
perl -T $I_lib ./check_riak_stats.pl --all
hr
perl -T $I_lib ./check_riak_stats.pl -s ring_num_partitions -c 64:64 -v
hr
perl -T $I_lib ./check_riak_stats.pl -s disk.0.size -c 1024: -v
hr
perl -T $I_lib ./check_riak_write.pl
hr
perl -T $I_lib ./check_riak_version.pl

echo "
# ============================================================================ #
# ============================================================================ #
"
