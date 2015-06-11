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

set -u
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

# even bare 'nodetool status' has broken environment in Travis, nothing to do with say Taint security
#nodetool status
# CASSANDRA_HOST and CASSANDRA_CONF obtained via .travis.yml
# workarounds for nodetool "You must set the CASSANDRA_CONF and CLASSPATH vars"
export CASSANDRA_HOME="${CASSANDRA_HOME:-/usr/local/cassandra}"
export CASSANDRA_CONF="${CASSANDRA_CONF:-$CASSANDRA_HOME/conf}"
#export CLASSPATH="${CLASSPATH:-.}"
for x in $(find /usr/local/cassandra -name '*.jar'); do
    export CLASSPATH="CLASSPATH:$x"
done
echo "using CLASSPATH=$CLASSPATH"
#find "$CASSANDRA_HOME" -name '*cassandra.in.sh*'
# doesn't work
#set +u
#for x in $(find "$CASSANDRA_HOME" -name '*cassandra.in.sh*'); do
#    echo "sourcing $x"
#    . "$x"
#done
#set -u
perl -T $I_lib ./check_cassandra_balance.pl
hr
perl -T $I_lib ./check_cassandra_heap.pl -vvv
hr
perl -T $I_lib ./check_cassandra_netstats.pl -vvv
hr
perl -T $I_lib ./check_cassandra_tpstats.pl

echo; echo

echo "
# ============================================================================ #
#                           E l a s t i c s e a r c h
# ============================================================================ #
"

# ELASTICSEARCH_HOST, ELASTICSEARCH_INDEX obtained via .travis.yml
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
hr
perl -T $I_lib ./check_elasticsearch.pl -v
hr
perl -T $I_lib ./check_elasticsearch_fielddata.pl --list-nodes
hr
perl -T $I_lib ./check_elasticsearch_index_exists.pl --list-indices
hr
perl -T $I_lib ./check_elasticsearch_cluster_shards.pl
hr
perl -T $I_lib ./check_elasticsearch_cluster_status.pl
hr
perl -T $I_lib ./check_elasticsearch_cluster_status_nodes_shards.pl
hr
perl -T $I_lib ./check_elasticsearch_data_nodes.pl -w 1
hr
perl -T $I_lib ./check_elasticsearch_fielddata.pl -N 127.0.0.1
hr
perl -T $I_lib ./check_elasticsearch_index_exists.pl
#hr
#perl -T $I_lib ./check_elasticsearch_index_health.pl
hr
perl -T $I_lib ./check_elasticsearch_index_replicas.pl
hr
perl -T $I_lib ./check_elasticsearch_index_settings.pl
hr
perl -T $I_lib ./check_elasticsearch_index_shards.pl
hr
perl -T $I_lib ./check_elasticsearch_index_stats.pl
hr
perl -T $I_lib ./check_elasticsearch_master_node.pl
hr
perl -T $I_lib ./check_elasticsearch_nodes.pl -w 1
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

# MEMCACHED_HOST obtained via .travis.yml
echo -ne "add myKey 0 100 4\r\nhari\r\n" | nc localhost 11211
perl -T $I_lib ./check_memcached_write.pl
perl -T $I_lib ./check_memcached_key.pl -k myKey -e hari
perl -T $I_lib ./check_memcached_stats.pl -w 20 -c 30 -vvv

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
perl -T $I_lib ./check_mysql_query.pl -q "show tables in information_schema" -vv -o CHARACTER_SETS

echo; echo

echo "
# ============================================================================ #
#                                   N e o 4 J
# ============================================================================ #
"

neo4j-shell -c 'CREATE (p:Person { name: "Hari Sekhon" })'
hr
# NEO4J_HOST obtained via .travis.yml
perl -T $I_lib ./check_neo4j_readonly.pl
hr
perl -T $I_lib ./check_neo4j_remote_shell_enabled.pl
hr
perl -T $I_lib ./check_neo4j_stats.pl
hr
perl -T $I_lib ./check_neo4j_store_sizes.pl -vvv
hr
perl -T $I_lib ./check_neo4j_version.pl

echo; echo

echo "
# ============================================================================ #
#                                   R e d i s
# ============================================================================ #
"

echo set myKey hari | redis-cli
# RIAK_HOST obtained via .travis.yml
perl -T $I_lib ./check_redis_clients.pl
hr
perl -T $I_lib ./check_redis_config.pl
hr
perl -T $I_lib ./check_redis_key.pl -k myKey -e hari
hr
perl -T $I_lib ./check_redis_publish_subscribe.pl
hr
perl -T $I_lib ./check_redis_stats.pl
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

# don't use new bucket types yet
#curl -XPUT localhost:8098/types/myType/buckets/myBucket/keys/myKey -d 'hari'
curl -XPUT localhost:8098/buckets/myBucket/keys/myKey -d 'hari'
echo
# RIAK_HOST obtained via .travis.yml
# needs sudo
#perl -T $I_lib ./check_riak_diag.pl
#hr
perl -T $I_lib ./check_riak_key.pl -b myBucket -k myKey -e hari
hr
# needs sudo
#perl -T $I_lib ./check_riak_ringready.pl
#hr
perl -T $I_lib ./check_riak_stats.pl --all-metrics
hr
perl -T $I_lib ./check_riak_write.pl

echo "
# ============================================================================ #
# ============================================================================ #
"
