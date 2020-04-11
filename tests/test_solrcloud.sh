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

# shellcheck disable=SC1090
. "$srcdir2/utils.sh"

srcdir="$srcdir2"

section "S o l r C l o u d"

export SOLRCLOUD_VERSIONS="${*:-${SOLRCLOUD_VERSIONS:-4.10 5.5 6.0 6.1 6.2 6.3 6.4 6.5 6.6 7.0 7.1 7.2 7.3 7.4 7.5 7.6 latest}}"

SOLR_HOST="${DOCKER_HOST:-${SOLR_HOST:-${HOST:-localhost}}}"
SOLR_HOST="${SOLR_HOST##*/}"
export SOLR_HOST="${SOLR_HOST%%:*}"
export SOLR_PORT_DEFAULT=8983
export HAPROXY_PORT_DEFAULT=8983
export SOLR_ZOOKEEPER_PORT_DEFAULT=9983
export SOLR_PORTS="$SOLR_PORT_DEFAULT 8984 $SOLR_ZOOKEEPER_PORT_DEFAULT"
export ZOOKEEPER_HOST="$SOLR_HOST"

export SOLR_HOME="/solr"
export DOCKER_MOUNT_DIR="/pl"

startupwait 30

check_docker_available

trap_debug_env solr zookeeper

# TODO: separate solrcloud and solrcloud-dev checks
test_solrcloud(){
    local version="$1"
    # SolrCloud 4.x needs some different args / locations
    if [ "${version:0:1}" = 4 ]; then
        four=true
        export SOLR_COLLECTION="collection1"
    else
        four=""
        export SOLR_COLLECTION="gettingstarted"
    fi
    section2 "Setting up SolrCloud $version docker test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting SolrCloud dynamic port mappings:"
    docker_compose_port SOLR_PORT "Solr HTTP"
    docker_compose_port "Solr ZooKeeper"
    DOCKER_SERVICE=solrcloud-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$SOLR_HOST" "$SOLR_PORT" "$SOLR_ZOOKEEPER_PORT"
    hr
    when_url_content "http://$SOLR_HOST:$SOLR_PORT/solr/" "Solr Admin"
    hr
    echo "checking HAProxy SolrCloud:"
    when_url_content "http://$SOLR_HOST:$HAPROXY_PORT/solr/" "Solr Admin"
    hr
    local DOCKER_CONTAINER
    DOCKER_CONTAINER="$(docker-compose ps | grep -v haproxy | sed -n '3s/ .*//p')"
    echo "container is $DOCKER_CONTAINER"
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    if [ "$version" = "latest" ]; then
        version="$(dockerhub_latest_version solrcloud-dev)"
    fi
    hr

    solrcloud_tests

    solrcloud_conn_refused_tests

    echo
    section2 "HAProxy SolrCloud tests:"
    echo

    SOLR_PORT="$HAPROXY_PORT" \
    solrcloud_tests

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count SolrCloud tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr
    echo
}

solrcloud_tests(){
    run ./check_solr_version.py -e "$version"

    run_fail 2 ./check_solr_version.py -e "fail-version"

    # defined in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "will try cluster status for up to $startupwait secs to give cluster and collection chance to initialize properly:"
    # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
    # shellcheck disable=SC2154
    retry "$startupwait" "$perl" -T ./check_solrcloud_cluster_status.pl
    hr

    run "$perl" -T ./check_solrcloud_cluster_status.pl -v

    docker_exec check_solrcloud_cluster_status_zookeeper.pl -H localhost -P 9983 -b / -v

    # FIXME: doesn't pick up collection from env
    if [ -n "$four" ]; then
        docker_exec check_solrcloud_config_zookeeper.pl -H localhost -P 9983 -b / -C "$SOLR_COLLECTION" -d "/solr/node1/solr/$SOLR_COLLECTION/conf" -v
    else
        # TODO: review why there is no solrcloud example config - this was the closest one I found via:
        # find /solr/ -name solrconfig.xml | while read filename; dirname=$(dirname $filename); do echo $dirname; /pl/check_solrcloud_config_zookeeper.pl -H localhost -P 9983 -b / -C gettingstarted -d $dirname -v; echo; done
        set +o pipefail
        if [ "$version" = "latest" ] ||
           [ "${version:0:1}" -ge 7 ]; then
            ERRCODE=2 docker_exec check_solrcloud_config_zookeeper.pl -H localhost -P 9983 -b / -C "$SOLR_COLLECTION" -d "$SOLR_HOME/server/solr/configsets/sample_techproducts_configs/conf" -v
        else
            ERRCODE=2 docker_exec check_solrcloud_config_zookeeper.pl -H localhost -P 9983 -b / -C "$SOLR_COLLECTION" -d "$SOLR_HOME/server/solr/configsets/data_driven_schema_configs/conf" -v #| grep -F '1 file only found in ZooKeeper but not local directory (configoverlay.json)'
        fi
        set -o pipefail
    fi

    # FIXME: why is only 1 node up instead of 2
    run "$perl" -T ./check_solrcloud_live_nodes.pl -w 1 -c 1 -t 60 -v

    docker_exec check_solrcloud_live_nodes_zookeeper.pl -H localhost -P 9983 -b / -w 1 -c 1 -v

    # docker is running slow
    run "$perl" -T ./check_solrcloud_overseer.pl -t 60 -v

    docker_exec check_solrcloud_overseer_zookeeper.pl -H localhost -P 9983 -b / -v

    # returns blank now
    #container_ip="$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$DOCKER_CONTAINER")"
    container_ip="$(docker-compose exec "$DOCKER_SERVICE" ip addr | awk '/inet .* e/{print $2}' | sed 's/\/.*//')"
    echo "container IP is $container_ip"
    docker_exec check_solrcloud_server_znode.pl -H localhost -P 9983 -z "/live_nodes/$container_ip:8983_solr" -v

    # FIXME: second node does not come/stay up
    # docker_exec check_solrcloud_server_znode.pl -H localhost -P 9983 -z /live_nodes/$(docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$DOCKER_CONTAINER"):8984_solr -v

    if [ -n "$four" ]; then
        docker_exec check_zookeeper_config.pl -H localhost -P 9983 -C "$SOLR_HOME/node1/solr/zoo.cfg" --no-warn-extra -v
    else
        docker_exec check_zookeeper_config.pl -H localhost -P 9983 -C "$SOLR_HOME/example/cloud/node1/solr/zoo.cfg" --no-warn-extra -v
    fi
}

solrcloud_conn_refused_tests(){
    run_conn_refused ./check_solr_version.py -e "$version"
    run_conn_refused "$perl" -T ./check_solrcloud_cluster_status.pl -v
    run_conn_refused "$perl" -T ./check_solrcloud_live_nodes.pl -w 1 -c 1 -t 60 -v
    run_conn_refused "$perl" -T ./check_solrcloud_overseer.pl -t 60 -v
}

run_test_versions SolrCloud

if is_CI; then
    docker_image_cleanup
    echo
fi
