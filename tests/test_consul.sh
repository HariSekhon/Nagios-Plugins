#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-01-26 23:36:03 +0000 (Tue, 26 Jan 2016)
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

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

echo "
# ============================================================================ #
#                                  C o n s u l
# ============================================================================ #
"

CONSUL_HOST="${DOCKER_HOST:-${CONSUL_HOST:-${HOST:-localhost}}}"
CONSUL_HOST="${CONSUL_HOST##*/}"
CONSUL_HOST="${CONSUL_HOST%%:*}"
export CONSUL_HOST

export CONSUL_PORT="${CONSUL_PORT:-8500}"

export DOCKER_IMAGE="harisekhon/consul"
export DOCKER_CONTAINER="nagios-plugins-consul"

startupwait=10

echo "Setting up Consul test container"
hr
DOCKER_CMD="agent -dev -data-dir /tmp -client 0.0.0.0"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" $CONSUL_PORT

hr
testkey="nagios/consul/testkey1"
echo "Writing random value to test key $testkey"
random_val=$RANDOM
curl -X PUT -d "$random_val" "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$testkey"
echo
hr
./check_consul_key.py -k /nagios/consul/testkey1 -r "^$random_val$" -v
hr
echo "writing deterministic test key to check thresholds"
curl -X PUT -d "5" "http://$CONSUL_HOST:$CONSUL_PORT/v1/kv/$testkey"
echo
hr
./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 5 -v
hr
./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -c 5 -v
hr
./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 5 -c 5 -v
hr
echo "checking threshold failures are caught correctly"
hr
set +o pipefail
./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 4 -c 5 -v | tee /dev/stderr | grep --color=yes ^WARNING
hr
./check_consul_key.py -k /nagios/consul/testkey1 -r '^\d$' -w 4 -c 4 -v | tee /dev/stderr | grep --color=yes ^CRITICAL
set -o pipefail
hr
./check_consul_write.py -v
hr
delete_container
