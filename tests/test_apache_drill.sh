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
#                            A p a c h e   D r i l l
# ============================================================================ #
"

export APACHE_DRILL_VERSIONS="${2:-0.7 0.8 0.9 1.0 1.1 1.2 1.3 1.4 1.5 1.6 latest}"
if is_travis; then
    export APACHE_DRILL_VERSIONS="${2:-1.6 latest}"
fi

APACHE_DRILL_HOST="${DOCKER_HOST:-${APACHE_DRILL_HOST:-${HOST:-localhost}}}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST##*/}"
APACHE_DRILL_HOST="${APACHE_DRILL_HOST%%:*}"
export APACHE_DRILL_HOST

export DOCKER_IMAGE="harisekhon/zookeeper"
export DOCKER_CONTAINER="nagios-plugins-zookeeper-test"

export DOCKER_IMAGE2="harisekhon/apache-drill"
export DOCKER_CONTAINER2="nagios-plugins-drill-test"

test_drill(){
    local version="$1"
    local startupwait=30
    travis_sample || continue
    hr
    echo "Setting up Apache Drill $version test container"
    hr
    echo "lauching drill container linked to zookeeper"
    local DOCKER_OPTS="--link $DOCKER_CONTAINER:zookeeper"
    local DOCKER_CMD="supervisord -n"
    launch_container "$DOCKER_IMAGE2:$version" "$DOCKER_CONTAINER2" 8047
    if [ -n "${NOTESTS:-}" ]; then
        return 0
    fi
    if [ "$version" = "latest" ]; then
        local version="*"
    fi
    hr
    set +e
    found_version=$(docker exec  "$DOCKER_CONTAINER2" ls / | grep apache-drill | tee /dev/stderr | tail -n1 | sed 's/.*-//')
    set -e
    if [[ "$found_version" != $version* ]]; then
        echo "Docker container version does not match expected version! (found '$found_version', expected '$version')"
        exit 1
    fi
    hr
    echo "found Apache Drill version $found_version"
    hr
    ./check_apache_drill_version.py -v -e "$version"
    hr
    ./check_apache_drill_status.py -v
    hr
    $perl -T $I_lib ./check_apache_drill_metrics.pl -v
    hr
    delete_container "$DOCKER_CONTAINER2"
    echo
}

startupwait=1
echo "launching zookeeper container"
launch_container "$DOCKER_IMAGE" "$DOCKER_CONTAINER" 2181 3181 4181

for version in $APACHE_DRILL_VERSIONS; do
    test_drill $version
done

delete_container "$DOCKER_CONTAINER"
echo
