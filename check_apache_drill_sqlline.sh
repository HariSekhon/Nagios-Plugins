#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-08-02 19:21:55 +0100 (Thu, 02 Aug 2018)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

exec 2>&1

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

export PATH="$PATH:/opt/apache-drill/bin:/apache-drill/bin"
for x in /opt/mapr/drill/drill-*/bin; do
    export PATH="$PATH:$x"
done

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

trap "exit $UNKNOWN" EXIT

# nice try but doesn't work
#export TMOUT=10
#exec

host="${APACHE_DRILL_HOST:-${DRILL_HOST:-${HOST:-localhost}}}"
zookeepers="${ZOOKEEPERS:-}"
cli="sqlline"

usage(){
    if [ -n "$*" ]; then
        echo "$@"
        echo
    fi
    cat <<EOF

Nagios Plugin to check Apache Drill via local sqlline shell SQL query

Specify --host to check a single Drill node, otherwise --zookeeper to test that some node is up. ZooKeeper ensemble takes priority

Tested on Apache Drill 1.13

usage: ${0##*/}

-H --host       Apache Drill Host (default: localhost, \$APACHE_DRILL_HOST, \$DRILL_HOST, \$HOST)
-z --zookeeper  ZooKeeper ensemble (comma separated list of hosts, \$ZOOKEEPERS)

EOF
    exit 1
}

until [ $# -lt 1 ]; do
    case $1 in
         -H|--host)     host="${2:-}"
                        shift
                        ;;
   -z|--zookeepers)     zookeeper="${2:-}"
                        shift
                        ;;
         -h|--help)     usage
                        ;;
                *)      usage "unknown argument: $1"
                        ;;
    esac
    shift || :
done

check_bin(){
    local bin="$1"
    if ! which $bin &>/dev/null; then
        echo "'$bin' command not found in \$PATH ($PATH)"
        exit $UNKNOWN
    fi
}
check_bin "$cli"

check_apache_drill(){
    local query="select * from sys.version;"
    if [ -n "$zookeepers" ]; then
        output="$("$cli" -u "jdbc:drill:zk=$zookeepers" -f /dev/stdin <<< "$query" 2>&1)"
        retcode=$?
    else
        output="$("$cli" -u "jdbc:drill:drillbit=$host" -f /dev/stdin <<< "$query" 2>&1)"
        retcode=$?
    fi
    trap '' EXIT
    if [ $retcode = 0 ]; then
        if grep -q "1 row selected" <<< "$output"; then
            echo "OK: Apache Drill query succeeded, SQL engine running"
            exit $OK
        fi
    fi
    echo "CRITICAL: Apache Drill query failed, SQL engine not running"
    exit $CRITICAL
}

#sleep 11
check_apache_drill
