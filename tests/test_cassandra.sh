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
#  https://www.linkedin.com/in/harisekhon
#

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                               C a s s a n d r a
# ============================================================================ #
"

CASSANDRA_HOST="${DOCKER_HOST:-${CASSANDRA_HOST:-${HOST:-localhost}}}"
CASSANDRA_HOST="${CASSANDRA_HOST##*/}"
CASSANDRA_HOST="${CASSANDRA_HOST%%:*}"
export CASSANDRA_HOST

export DOCKER_IMAGE="harisekhon/cassandra-dev"
export DOCKER_CONTAINER="nagios-plugins-cassandra-test"

export CASSANDRA_TEST_VERSIONS="${1:-1.2 2.0 2.1 2.2 3.0 3.5}"
if is_travis; then
    export CASSANDRA_TEST_VERSIONS="${1:-1.2 2.0}"
fi

export MNTDIR="/pl"

startupwait=10

if ! is_docker_available; then
    echo 'WARNING: Docker not found, skipping Cassandra checks!!!'
    exit 0
fi

docker_exec(){
    docker exec -ti "$DOCKER_CONTAINER" $MNTDIR/$@
}


test_cassandra(){
    local version="$1"
    travis_sample || continue
    echo "Setting up Cassandra $version test container"
    DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
    launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" 7199 9042
    hr
    docker exec -ti "$DOCKER_CONTAINER" nodetool status
    hr
    docker_exec check_cassandra_version_nodetool.py -e "$version"
    hr
    # Dockerized Cassandra doesn't seem able to detect it's own token % - even when container has been running for a long time
    # TODO: add more specific command testing here to only except that scenario
    docker_exec check_cassandra_balance.pl -v
    hr
    docker_exec check_cassandra_balance.pl --nodetool /cassandra/bin/nodetool -v
    hr
    docker_exec check_cassandra_heap.pl -w 70 -c 90 -v
    hr
    docker_exec check_cassandra_heap.pl --nodetool /cassandra/bin/nodetool -w 70 -c 90 -v
    hr
    docker_exec check_cassandra_netstats.pl -v
    hr
    docker_exec check_cassandra_netstats.pl --nodetool /cassandra/bin/nodetool -v
    hr
    docker_exec check_cassandra_nodes.pl -v
    hr
    docker_exec check_cassandra_nodes.pl --nodetool /cassandra/bin/nodetool -v
    hr
    docker_exec check_cassandra_tpstats.pl -v
    hr
    docker_exec check_cassandra_tpstats.pl --nodetool /cassandra/bin/nodetool -v
    hr
    delete_container
    hr
    echo; echo
}

for version in $CASSANDRA_TEST_VERSIONS; do
    test_cassandra $version
done

# ============================================================================ #
#                                     E N D
# ============================================================================ #
exit 0
# ============================================================================ #
# Cassandra build in Travis is quite broken, appears due to an incorrect upgrade in the VM image

# workarounds for nodetool "You must set the CASSANDRA_CONF and CLASSPATH vars"
# even bare 'nodetool status' has broken environment in Travis, nothing to do with say Taint security
# Cassandra service on Travis is really broken, some hacks to make it work
if [ -n "${TRAVIS:-}" ]; then
#if false; then
    export CASSANDRA_HOME="${CASSANDRA_HOME:-/usr/local/cassandra}"
    # these were only necessary on the debug VM but not in the actual Travis env for some reason
    #sudo sed -ibak 's/jamm-0.2.5.jar/jamm-0.2.8.jar/' $CASSANDRA_HOME/bin/cassandra.in.sh $CASSANDRA_HOME/conf/cassandra-env.sh
    #sudo sed -ribak 's/^(multithreaded_compaction|memtable_flush_queue_size|preheat_kernel_page_cache|compaction_preheat_key_cache|in_memory_compaction_limit_in_mb):.*//' $CASSANDRA_HOME/conf/cassandra.yaml
    # stop printing xss = $JAVA_OPTS which will break nodetool parsing
    sudo sed -ibak2 's/^echo "xss = .*//' $CASSANDRA_HOME/conf/cassandra-env.sh
    sudo service cassandra status || sudo service cassandra start
    hr
fi

# /usr/local/bin/nodetool symlink doesn't source cassandra.in.sh properly
nodetool status || :
/usr/local/cassandra/bin/nodetool status || :
hr
# Cassandra checks are broken due to broken nodetool environment
# must set full path to /usr/local/cassandra/bin/nodetool to bypass /usr/local/bin/nodetool symlink which doesn't source cassandra.in.sh properly and breaks with "You must set the CASSANDRA_CONF and CLASSPATH vars@
$perl -T $I_lib ./check_cassandra_balance.pl  -n /usr/local/cassandra/bin/nodetool -v
hr
$perl -T $I_lib ./check_cassandra_heap.pl     -n /usr/local/cassandra/bin/nodetool -w 70 -c 90 -v
hr
$perl -T $I_lib ./check_cassandra_netstats.pl -n /usr/local/cassandra/bin/nodetool -v
hr
$perl -T $I_lib ./check_cassandra_nodes.pl -n /usr/local/cassandra/bin/nodetool -v
hr
$perl -T $I_lib ./check_cassandra_tpstats.pl  -n /usr/local/cassandra/bin/nodetool -v

echo; echo
