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
find / -iname cassandra 2>/dev/null
ps -ef|grep -i cassandra
# CASSANDRA_HOST and CASSANDRA_CONF obtained via .travis.yml
export CASSANDRA_CONF="${CASSANDRA_CONF:-/usr/local/cassandra/conf}"
export CLASSPATH="${CLASSPATH:-.}" # workaround for nodetool "You must set the CASSANDRA_CONF and CLASSPATH vars"
for x in /usr/local/cassandra/lib/*.jar; do
    export CLASSPATH="CLASSPATH:$x"
done
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
curl -XPUT "http://localhost:9200/$ELASTICSEARCH_INDEX/"
hr
perl -T $I_lib ./check_elasticsearch_fielddata.pl --list-nodes
hr
perl -T $I_lib ./check_elasticsearch_index_exists.pl --list-indices
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
perl -T $I_lib ./check_elasticsearch_nodes.pl
#hr
#perl -T $I_lib ./check_elasticsearch_node_stats.pl
hr
echo "sleeping for 300 secs to allow shard to get assigned and cluster to settle"
sleep 300
perl -T $I_lib ./check_elasticsearch_shards_detail.pl
hr
perl -T $I_lib ./check_elasticsearch_cluster_status.pl
hr
perl -T $I_lib ./check_elasticsearch_cluster_shards.pl
hr
perl -T $I_lib ./check_elasticsearch_cluster_status_nodes_shards.pl
hr
perl -T $I_lib ./check_elasticsearch.pl -v

echo; echo

echo "
# ============================================================================ #
#                               M e m c a c h e d
# ============================================================================ #
"

# MEMCACHED_HOST obtained via .travis.yml
perl -T $I_lib ./check_memcached_write.pl
#perl -T $I_lib ./check_memcached_key.pl -k test -e hari
perl -T $I_lib ./check_memcached_stats.pl

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
perl -T $I_lib ./check_mysql_config.pl
hr
perl -T $I_lib ./check_mysql_query.pl -q "show tables in information_schema" -vv -o CHARACTER_SETS

echo; echo

echo "
# ============================================================================ #
#                                   N e o 4 J
# ============================================================================ #
"

# NEO4J_HOST obtained via .travis.yml
perl -T $I_lib ./check_neo4j_readonly.pl
hr
perl -T $I_lib ./check_neo4j_remote_shell_enabled.pl
hr
perl -T $I_lib ./check_neo4j_stats.pl
hr
perl -T $I_lib ./check_neo4j_store_sizes.pl
hr
perl -T $I_lib ./check_neo4j_version.pl

echo; echo

echo "
# ============================================================================ #
#                                   R e d i s
# ============================================================================ #
"

# RIAK_HOST obtained via .travis.yml
perl -T $I_lib ./check_redis_clients.pl
hr
perl -T $I_lib ./check_redis_config.pl
#hr
# no key yet
#perl -T $I_lib ./check_redis_key.pl -k test -e hari
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

# RIAK_HOST obtained via .travis.yml
# needs sudo
#perl -T $I_lib ./check_riak_diag.pl
#hr
# no key yet
#perl -T $I_lib ./check_riak_key.pl -k somekey
#hr
# needs sudo
#perl -T $I_lib ./check_riak_ringready.pl
hr
perl -T $I_lib ./check_riak_stats.pl --all-metrics
hr
perl -T $I_lib ./check_riak_write.pl

echo "
# ============================================================================ #
# ============================================================================ #
"
