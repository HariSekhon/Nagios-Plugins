#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-03-14 18:38:24 +0000 (Wed, 14 Mar 2018)
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
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/.."

# shellcheck disable=SC1090
. "$srcdir/utils.sh"

section "V a u l t"

export VAULT_VERSIONS="${*:-${VAULT_VERSIONS:-0.6.5 0.7.3 0.8.3 0.9.5 latest}}"

VAULT_HOST="${DOCKER_HOST:-${VAULT_HOST:-${HOST:-localhost}}}"
VAULT_HOST="${VAULT_HOST##*/}"
VAULT_HOST="${VAULT_HOST%%:*}"
export VAULT_HOST

export VAULT_PORT_DEFAULT=8200
export HAPROXY_PORT_DEFAULT=8200

check_docker_available

trap_debug_env vault

test_vault(){
    local version="$1"
    section2 "Setting up Vault $version test container"
    docker_compose_pull
    VERSION="$version" docker-compose up -d --remove-orphans
    hr
    echo "getting Vault dynamic port mapping:"
    docker_compose_port "Vault"
    DOCKER_SERVICE=vault-haproxy docker_compose_port HAProxy
    hr
    # shellcheck disable=SC2153
    when_ports_available "$VAULT_HOST" "$VAULT_PORT" "$HAPROXY_PORT"
    hr
    when_url_content "http://$VAULT_HOST:$VAULT_PORT/v1/sys/health" "cluster_name"
    hr
    echo "checking HAProxy Vault:"
    when_url_content "http://$VAULT_HOST:$HAPROXY_PORT/v1/sys/health" "cluster_name"
    hr
    if [ -n "${NOTESTS:-}" ]; then
        exit 0
    fi

    if [ "$version" = "latest" ]; then
        version=".*"
    fi

    vault_tests

    echo

    section2 "Running HAProxy tests"

    VAULT_PORT="$HAPROXY_PORT" \
    vault_tests

    [ -n "${KEEPDOCKER:-}" ] ||
    docker-compose down
    hr

    # defined and tracked in bash-tools/lib/utils.sh
    # shellcheck disable=SC2154
    echo "Completed $run_count Vault tests"
    hr
    echo
}

vault_tests(){
    run ./check_vault_version.py -e "$version"

    run ./check_vault_health.py

    run_fail 1 ./check_vault_health.py -w 0.0001

    run_fail 2 ./check_vault_health.py -c 0.0001

    run ./check_vault_health.py --standby

    run_fail 2 ./check_vault_health.py --sealed

    run ./check_vault_health.py --unsealed

    run_usage ./check_vault_health.py --sealed --unsealed

    run_conn_refused ./check_vault_health.py

    run_fail 2 ./check_vault_high_availability.py

    run_fail 2 ./check_vault_high_availability.py --leader
}

run_test_versions Vault

if is_CI; then
    docker_image_cleanup
    echo
fi
