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

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "E l a s t i c s e a r c h"

# Elasticsearch 6.0+ only available on new docker.elastic.co which uses full sub-version x.y.z and does not have x.y tags
# Any version given as x.y.z will use docker.elastic.co repo, otherwise old dockerhub images
# Platinum edition with X-Pack is only available from 6.x onwards from docker.elastic.co - no longer available in 7.x due to being rolled in to standard
export ELASTICSEARCH_VERSIONS="${*:-${ELASTICSEARCH_VERSIONS:-
    1.3 1.4 1.5 1.6 1.7 2.0 2.1 2.2 2.3 2.4 5.0 5.1 5.2 5.3 5.4 5.5 5.6
        5.2.1 5.3.3 5.4.3 5.5.3 5.6.8 6.0.1 6.1.4 6.2.4 6.3.2 6.4.3 6.5.4 6.6.2 6.7.2 6.8.0 7.0.1 7.1.1
            6.0.1-x-pack 6.1.4-x-pack 6.2.4-x-pack
}}"  # latest tag was removed from dockerhub :-/

ELASTICSEARCH_HOST="${DOCKER_HOST:-${ELASTICSEARCH_HOST:-${HOST:-localhost}}}"
ELASTICSEARCH_HOST="${ELASTICSEARCH_HOST##*/}"
ELASTICSEARCH_HOST="${ELASTICSEARCH_HOST%%:*}"
export ELASTICSEARCH_HOST
export ELASTICSEARCH_PORT_DEFAULT=9200
export HAPROXY_PORT_DEFAULT=9200
export ELASTICSEARCH_INDEX="${ELASTICSEARCH_INDEX:-test}"
export X_PACK=0

export HAPROXY_USER="esuser"
export HAPROXY_PASSWORD="espass"

check_docker_available

trap_debug_env elasticsearch

# Elasticsearch 5.x takes ~ 50 secs to start up, sometimes doesn't start after 90 secs :-/
startupwait 120

# Elasticsearch 5.0 may fail to start up properly complaining about vm.max_map_count, fix is to do:
#
#  sudo sysctl -w vm.max_map_count=232144
#  grep vm.max_map_count /etc/sysctl.d/99-elasticsearch.conf || echo vm.max_map_count=232144 >> /etc/sysctl.d/99-elasticsearch.conf

remove_shard_replicas(){
        echo "removing replicas of all indices to avoid failing tests with unassigned shards:"
        set +o pipefail
        # $perl defined in bash-tools/lib/perl.sh (imported by utils.sh)
        # shellcheck disable=SC2154
        "$perl" -T ./check_elasticsearch_index_exists.pl --list-indices |
        tail -n +2 |
        grep -v "^[[:space:]]*$" |
        while read -r index; do
            echo "reducing replicas for index '$index'"
            # shellcheck disable=SC2153
            curl -u "${ELASTICSEARCH_USER:-}:${ELASTICSEARCH_PASSWORD:-}" -H "content-type: application/json" -XPUT "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/$index/_settings" -d '
            {
                "index": {
                    "number_of_replicas": 0
                }
            }
            '
            echo
        done
        set -o pipefail
}

test_elasticsearch(){
    local version="$1"
    section2 "Setting up Elasticsearch $version test container"
    # re-enable this when Elastic.co finally support 'latest' tag
    #if [ "$version" != "latest" ] && [ "${version:0:1}" -ge 6 ]; then
    if grep -Eq '^[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$' <<< "$version"; then
        local export COMPOSE_FILE="$srcdir/docker/$DOCKER_SERVICE-elastic.co-docker-compose.yml"
    elif grep -Eq '^[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+-x-pack$' <<< "$version"; then
        local version="${version%-x-pack}"
        export COMPOSE_FILE="$srcdir/docker/$DOCKER_SERVICE-platinum-docker-compose.yml"
        export ELASTICSEARCH_USER="elastic"
        export ELASTICSEARCH_PASSWORD="password"
        local export HAPROXY_USER="elastic"
        local export HAPROXY_PASSWORD="password"
        local export X_PACK=1
    fi
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Elasticsearch dynamic port mapping:"
    docker_compose_port "Elasticsearch"
    DOCKER_SERVICE=elasticsearch-haproxy docker_compose_port HAProxy
    hr
    when_ports_available "$ELASTICSEARCH_HOST" "$ELASTICSEARCH_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT" "lucene_version" -u "${ELASTICSEARCH_USER:-}:${ELASTICSEARCH_PASSWORD:-}"
    hr
    echo "checking HAProxy Elasticsearch with authentication:"
    when_url_content "http://$ELASTICSEARCH_HOST:$HAPROXY_PORT" "lucene_version" -u "$HAPROXY_USER:$HAPROXY_PASSWORD"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi
    # Travis added this
    #echo "deleting twitter index as 5 unassigned shards are breaking tests"
    #curl -XDELETE "http://localhost:9200/twitter" || :
    #curl -XDELETE "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/$ELASTICSEARCH_INDEX" || :
    # always returns 0 and I don't wanna parse the json error
    #if ! curl -s "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/$ELASTICSEARCH_INDEX" &>/dev/null; then
    if [ -z "${NODOCKER:-}" ]; then
        if ! "$perl" -T ./check_elasticsearch_index_exists.pl --list-indices | grep "^[[:space:]]*${ELASTICSEARCH_INDEX}[[:space:]]*$"; then
            echo "creating test Elasticsearch index '$ELASTICSEARCH_INDEX'"
            # Elasticsearch 6.0 insists on application/json header otherwise index is not created
            curl -iv -u "${ELASTICSEARCH_USER:-}:${ELASTICSEARCH_PASSWORD:-}" -H "content-type: application/json" -XPUT "http://$ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT/$ELASTICSEARCH_INDEX/" -d '
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
        fi
        hr
        remove_shard_replicas
        echo
        echo "Setup done, starting checks ..."
    fi
    hr
    if [ "$version" = "latest" ]; then
        local version=".*"
    fi
    elasticsearch_tests
    echo
    section2 "Running HAProxy + Authentication tests"
    ELASTICSEARCH_PORT="$HAPROXY_PORT" \
    ELASTICSEARCH_USER="$HAPROXY_USER" \
    ELASTICSEARCH_PASSWORD="$HAPROXY_PASSWORD" \
    elasticsearch_tests
    # TODO: run fail auth tests for all plugins and add run_fail_auth to bash-tools/utils.sh with run_grep string

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Elasticsearch tests"
    hr
    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
}

elasticsearch_tests(){
    run "$perl" -T ./check_elasticsearch.pl -v --es-version "$version"

    run_fail 2 "$perl" -T ./check_elasticsearch.pl -v --es-version "fail-version"

    run_conn_refused "$perl" -T ./check_elasticsearch.pl -v --es-version "$version"

    if [ "$X_PACK" = 1 ] || [  "${version:0:1}" -ge 7 ]; then
        local license_opts="--trial"
        if [ "${version:0:1}" -ge 7 ]; then
            license_opts="--basic"
        fi
        run ./check_elasticsearch_x-pack_license_expiry.py -w 20 $license_opts

        # fail with warning without --trial or --basic
        run_fail 1 ./check_elasticsearch_x-pack_license_expiry.py -w 20

        # fail with warning without --trial or --basic
        run_fail 1 ./check_elasticsearch_x-pack_license_expiry.py

        # basic license doesn't expire
        if [[ "$license_opts" =~ --basic ]]; then
            run ./check_elasticsearch_x-pack_license_expiry.py -c 30 $license_opts
        else
            run_fail 2 ./check_elasticsearch_x-pack_license_expiry.py -c 30 $license_opts
        fi

        run_conn_refused ./check_elasticsearch_x-pack_license_expiry.py $license_opts

        run_fail 3 ./check_elasticsearch_x-pack_feature_enabled.py -l

        if [[ "$license_opts" =~ --basic ]]; then
            # available but not enabled in the basic deployment
            run_fail 2 ./check_elasticsearch_x-pack_feature_enabled.py -f security
            # not available
            run_fail 2 ./check_elasticsearch_x-pack_feature_enabled.py -f logstash
            run_fail 2 ./check_elasticsearch_x-pack_feature_enabled.py -f ml
            run_fail 2 ./check_elasticsearch_x-pack_feature_enabled.py -f graph
            run_fail 2 ./check_elasticsearch_x-pack_feature_enabled.py -f watcher
        else
            run ./check_elasticsearch_x-pack_feature_enabled.py -f security
            run ./check_elasticsearch_x-pack_feature_enabled.py -f logstash
            run ./check_elasticsearch_x-pack_feature_enabled.py -f ml
            run ./check_elasticsearch_x-pack_feature_enabled.py -f graph
            run ./check_elasticsearch_x-pack_feature_enabled.py -f watcher
        fi

        run ./check_elasticsearch_x-pack_feature_enabled.py -f monitoring

        run_fail 2 ./check_elasticsearch_x-pack_feature_enabled.py -f nonexistentfeature

        run_conn_refused ./check_elasticsearch_x-pack_feature_enabled.py -f security
    fi

    # Listing checks return UNKNOWN
    set +e
    # _cat/fielddata API is no longer outputs lines for 0b fielddata nodes in Elasticsearch 5.0 - https://github.com/elastic/elasticsearch/issues/21564
    #export ELASTICSEARCH_NODE="$(DEBUG='' "$perl" -T ./check_elasticsearch_fielddata.pl --list-nodes | grep -v -e '^Nodes' -e '^Hostname' -e '^[[:space:]]*$' | awk '{print $1; exit}' )"
    # this works too but let's test the --list-nodes from one of the plugins
    #export ELASTICSEARCH_NODE="$(curl -s $HOST:9200/_nodes | python -c 'import json, sys; print json.load(sys.stdin)["nodes"].values()[0]["node"]')"
    # taking hostname not node name here, ip is $2, node name is $3
    ELASTICSEARCH_NODE="$(DEBUG='' "$perl" -T ./check_elasticsearch_node_disk_percent.pl --list-nodes | grep -vi -e '^Elasticsearch Nodes' -e '^Hostname' -e '^[[:space:]]*$' | awk '{print $1; exit}' )"
    export ELASTICSEARCH_NODE
    [ -n "$ELASTICSEARCH_NODE" ] || die "failed to determine Elasticsearch node name from API!"
    set -e
    echo "determined Elasticsearch node => $ELASTICSEARCH_NODE"
    hr
    run_fail 3 "$perl" -T ./check_elasticsearch_index_exists.pl --list-indices

    run_conn_refused "$perl" -T ./check_elasticsearch_index_exists.pl --list-indices

    run "$perl" -T ./check_elasticsearch_cluster_disk_balance.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_cluster_disk_balance.pl -v

    # recent versions of Elasticsearch create indices with shard replicas later so call this again late to ensure we don't hit unassigned shards
    remove_shard_replicas

    # no longer necessary since reducing monitoring index replication to zero
    #echo "waiting for shards to be allocated (takes longer in Elasticsearch 6.0):"
    #retry 10 "$perl" -T ./check_elasticsearch_cluster_shards.pl -v
    hr

    run "$perl" -T ./check_elasticsearch_cluster_shards.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_cluster_shards.pl -v

    # no longer necessary since reducing monitoring index replication to zero
    #echo "waiting for shard balance (takes longer in Elasticsearch 6.0):"
    #retry 10 "$perl" -T ./check_elasticsearch_cluster_shard_balance.pl -v
    #hr

    run "$perl" -T ./check_elasticsearch_cluster_shard_balance.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_cluster_shard_balance.pl -v

    run "$perl" -T ./check_elasticsearch_cluster_stats.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_cluster_stats.pl -v

    # travis has yellow status
    run_fail "0 1" "$perl" -T ./check_elasticsearch_cluster_status.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_cluster_status.pl -v

    remove_shard_replicas
    # didn't help with default monitoring index due to replication factor > 1 node, setting replication to zero was the fix
    #echo "waiting for cluster status, nodes and shards to pass (takes longer on Elasticsearch 6.0):"
    #retry 10 "$perl" -T ./check_elasticsearch_cluster_status_nodes_shards.pl -v
    #hr

    run "$perl" -T ./check_elasticsearch_cluster_status_nodes_shards.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_cluster_status_nodes_shards.pl -v

    run "$perl" -T ./check_elasticsearch_data_nodes.pl -w 1 -v

    run_conn_refused "$perl" -T ./check_elasticsearch_data_nodes.pl -w 1 -v

    run "$perl" -T ./check_elasticsearch_doc_count.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_doc_count.pl -v

    # _cat/fielddata API is no longer outputs lines for 0b fielddata nodes in Elasticsearch 5.0 - https://github.com/elastic/elasticsearch/issues/21564
    run "$perl" -T ./check_elasticsearch_fielddata.pl -N "$ELASTICSEARCH_NODE" -v

    run_conn_refused "$perl" -T ./check_elasticsearch_fielddata.pl -N "$ELASTICSEARCH_NODE" -v

    run "$perl" -T ./check_elasticsearch_index_exists.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_index_exists.pl -v

    # the field for this is not available in Elasticsearch 1.3
    if [ "$version" != 1.3  ]; then
        run "$perl" -T ./check_elasticsearch_index_age.pl -v -w 0:1
    fi

    run_conn_refused "$perl" -T ./check_elasticsearch_index_age.pl -v -w 0:1

    #run perl -T ./check_elasticsearch_index_health.pl -v

    #run_conn_refused perl -T ./check_elasticsearch_index_health.pl -v

    run "$perl" -T ./check_elasticsearch_index_replicas.pl -w 0 -v

    run_conn_refused "$perl" -T ./check_elasticsearch_index_replicas.pl -w 0 -v

    run "$perl" -T ./check_elasticsearch_index_settings.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_index_settings.pl -v

    run "$perl" -T ./check_elasticsearch_index_shards.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_index_shards.pl -v

    run "$perl" -T ./check_elasticsearch_index_stats.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_index_stats.pl -v

    run "$perl" -T ./check_elasticsearch_master_node.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_master_node.pl -v

    run "$perl" -T ./check_elasticsearch_nodes.pl -v -w 1

    run_conn_refused "$perl" -T ./check_elasticsearch_nodes.pl -v -w 1

    run "$perl" -T ./check_elasticsearch_node_disk_percent.pl -N "$ELASTICSEARCH_NODE" -v -w 99 -c 99

    run_conn_refused "$perl" -T ./check_elasticsearch_node_disk_percent.pl -N "$ELASTICSEARCH_NODE" -v -w 99 -c 99

    echo "checking threshold failure warning:"
    run_fail 1 "$perl" -T ./check_elasticsearch_node_disk_percent.pl -N "$ELASTICSEARCH_NODE" -v -w 1 -c 99

    echo "checking threshold failure critical:"
    run_fail 2 "$perl" -T ./check_elasticsearch_node_disk_percent.pl -N "$ELASTICSEARCH_NODE" -v -w 1 -c 2

    run "$perl" -T ./check_elasticsearch_node_shards.pl -N "$ELASTICSEARCH_NODE" -v

    run_conn_refused "$perl" -T ./check_elasticsearch_node_shards.pl -N "$ELASTICSEARCH_NODE" -v

    run "$perl" -T ./check_elasticsearch_node_stats.pl -N "$ELASTICSEARCH_NODE" -v

    run_conn_refused "$perl" -T ./check_elasticsearch_node_stats.pl -N "$ELASTICSEARCH_NODE" -v


    run "$perl" -T ./check_elasticsearch_shards_state_detail.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_shards_state_detail.pl -v

    run "$perl" -T ./check_elasticsearch_tasks_pending.pl -v

    run_conn_refused "$perl" -T ./check_elasticsearch_tasks_pending.pl -v

    run ./check_elasticsearch_tasks_slow.py

    run_fail 3 ./check_elasticsearch_tasks_slow.py --list-tasks

    run_fail 3 ./check_elasticsearch_tasks_slow.py --list-tasks --cluster-tasks

    run ./check_elasticsearch_tasks_slow.py --cluster-tasks

    run ./check_elasticsearch_tasks_slow.py --search-tasks

    run_usage ./check_elasticsearch_tasks_slow.py --cluster-tasks --search-tasks

    run_fail 1 ./check_elasticsearch_tasks_slow.py --warning 0.1

    run_fail 1 ./check_elasticsearch_tasks_slow.py --warning 0.1 --cluster-tasks

    run ./check_elasticsearch_tasks_slow.py --warning 0.1 --search-tasks

    run_fail 2 ./check_elasticsearch_tasks_slow.py --warning 0.1 --critical 0.1

    run_fail 2 ./check_elasticsearch_tasks_slow.py --warning 0.1 --critical 0.1 --cluster-tasks

    run ./check_elasticsearch_tasks_slow.py --warning 0.1 --critical 0.1 --search-tasks

    run_conn_refused ./check_elasticsearch_tasks_slow.py
}

run_test_versions Elasticsearch

if is_CI; then
    docker_image_cleanup
    echo
fi
