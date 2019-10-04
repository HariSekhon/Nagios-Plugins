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

trap "echo 'CRITICAL: Apache Drill check failed'; exit $CRITICAL" EXIT

# nice try but doesn't work
#export TMOUT=10
#exec

cli="sqlline"
jdbc_url=""

usage(){
    if [ -n "$*" ]; then
        echo "$@"
        echo
    fi
    cat <<EOF

Nagios Plugin to check Apache Drill via local sqlline shell SQL query

Specify host in the JDBC Url to check a specific Drill node (defaults to localhost), or zookeeper to test that any node is up

Tested on Apache Drill 1.7, 1.8, 1.9, 1.10, 1.11, 1.12, 1.13, 1.14

usage: ${0##*/}

-u   --jdbc-url     JDBC url to use to connect to Apache Drill, can omit jdbc:drill: prefix (defaults to jdbc:drill:drillbit=localhost)

EOF
    trap '' EXIT
    exit $UNKNOWN
}

until [ $# -lt 1 ]; do
    case $1 in
     -u|--jdbc-url)     jdbc_url="${2:-}"
                        shift || :
                        ;;
         -h|--help)     usage
                        ;;
                *)      usage "unknown argument: $1"
                        ;;
    esac
    shift || :
done

jdbc_url="${jdbc_url#jdbc:drill:}"
if [ -z "$jdbc_url" ]; then
    jdbc_url="drillbit=localhost"
fi
jdbc_url="jdbc:drill:$jdbc_url"
jdbc_url="${jdbc_url//\'}"
jdbc_url="${jdbc_url//\`}"
# could strip $() here too but probably not worth the fork to sed

check_bin(){
    local bin="$1"
    if ! type -P $bin &>/dev/null; then
        echo "'$bin' command not found in \$PATH ($PATH)"
        exit $UNKNOWN
    fi
}
check_bin "$cli"

check_apache_drill(){
    local query="select * from sys.version;"
    output="$("$cli" -u "$jdbc_url" -f /dev/stdin <<< "$query" 2>&1)"
    retcode=$?
    trap '' EXIT
    if [ $retcode = 0 ]; then
        if grep -q "1 row selected" <<< "$output"; then
            echo "OK: Apache Drill sqlline query succeeded, SQL engine running"
            exit $OK
        fi
    fi
    echo "CRITICAL: Apache Drill sqlline query failed, SQL engine not running or wrong jdbc-url / options"
    exit $CRITICAL
}

check_apache_drill
