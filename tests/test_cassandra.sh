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

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

section "C a s s a n d r a"

export CASSANDRA_VERSIONS="${@:-${CASANDRA_VERSIONS:-latest 1.2 2.0 2.1 2.2 3.0 3.5}}"

CASSANDRA_HOST="${DOCKER_HOST:-${CASSANDRA_HOST:-${HOST:-localhost}}}"
CASSANDRA_HOST="${CASSANDRA_HOST##*/}"
CASSANDRA_HOST="${CASSANDRA_HOST%%:*}"
export CASSANDRA_HOST
export CASSANDRA_PORT_DEFAULT="${CASSANDRA_PORT:-9042}"
export CASSANDRA_PORTS_DEFAULT="7199 $CASSANDRA_PORT"

export MNTDIR="/pl"

startupwait 10

check_docker_available

trap_debug_env cassandra

docker_exec(){
    #docker exec -ti "$DOCKER_CONTAINER" $MNTDIR/$@
    echo "docker-compose exec $DOCKER_SERVICE $MNTDIR/$@"
    docker-compose exec "$DOCKER_SERVICE" $MNTDIR/$@
}

test_cassandra(){
    local version="$1"
    echo "Setting up Cassandra $version test container"
    #DOCKER_OPTS="-v $srcdir/..:$MNTDIR"
    #launch_container "$DOCKER_IMAGE:$version" "$DOCKER_CONTAINER" $CASSANDRA_PORT
    VERSION="$version" docker-compose up -d
    export CASSANDRA_PORT="`docker-compose port "$DOCKER_SERVICE" "$CASSANDRA_PORT_DEFAULT" | sed 's/.*://'`"
    export CASSANDRA_PORTS=`{ for x in $CASSANDRA_PORTS_DEFAULT; do  docker-compose port "$DOCKER_SERVICE" "$x"; done; } | sed 's/.*://'`
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    when_ports_available "$startupwait" "$CASSANDRA_HOST" $cassandra_ports
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    hr
    docker-compose exec "$DOCKER_SERVICE" nodetool status
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
    #delete_container
    docker-compose down
    hr
    echo
    echo
}

run_test_versions Cassandra

# ============================================================================ #
#                                     E N D
# ============================================================================ #
exit 0
# ============================================================================ #
# Cassandra build in Travis is quite broken, appears due to an incorrect upgrade in the VM image

# workarounds for nodetool "You must set the CASSANDRA_CONF and CLASSPATH vars"
# even bare 'nodetool status' has broken environment in Travis, nothing to do with say Taint security
# Cassandra service on Travis is really broken, some hacks to make it work
if is_travis; then
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
$perl -T ./check_cassandra_balance.pl  -n /usr/local/cassandra/bin/nodetool -v
hr
$perl -T ./check_cassandra_heap.pl     -n /usr/local/cassandra/bin/nodetool -w 70 -c 90 -v
hr
$perl -T ./check_cassandra_netstats.pl -n /usr/local/cassandra/bin/nodetool -v
hr
$perl -T ./check_cassandra_nodes.pl -n /usr/local/cassandra/bin/nodetool -v
hr
$perl -T ./check_cassandra_tpstats.pl  -n /usr/local/cassandra/bin/nodetool -v

echo; echo
