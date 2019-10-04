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

export PATH="$PATH:/usr/hdp/current/hive-client/bin"

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

trap "echo 'CRITICAL: HiveServer2 check failed'; exit $CRITICAL" EXIT

# nice try but doesn't work
#export TMOUT=10
#exec

cli="beeline"
jdbc_url=""

usage(){
    if [ -n "$*" ]; then
        echo "$@"
        echo
    fi
    cat <<EOF

Nagios Plugin to check HiveServer2 via local beeline SQL query

Specify the host in the JDBC Url to check a specific HiveServer2 instance (defaults to localhost), or zookeeper to test that any HiveServer2 instance is up

JDBC URL can be copied and pasted from the Hive Summary page in Ambari (there is a clipboard button to the right of JDBC Url)

Tested on Hive 1.2.1 on Hortonworks HDP 2.6

usage: ${0##*/}

-u   --jdbc-url     JDBC url to use to connect to HiveServer2, can omit jdbc:hive2:// prefix (defaults to jdbc:hive2://localhost:10000/default)

EOF
    trap '' EXIT
    exit 1
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

jdbc_url="${jdbc_url#jdbc:hive2://}"
if [ -z "$jdbc_url" ]; then
    jdbc_url="localhost:10000/default"
fi
jdbc_url="jdbc:hive2://$jdbc_url"
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

check_hiveserver2_beeline(){
    local query="select 1;"
    output="$("$cli" -u "$jdbc_url" -f /dev/stdin <<< "$query" 2>&1)"
    retcode=$?
    trap '' EXIT
    if [ $retcode = 0 ]; then
        if grep -q "1 row selected" <<< "$output"; then
            echo "OK: HiveServer2 beeline query succeeded, SQL engine running"
            exit $OK
        fi
    fi
    echo "CRITICAL: HiveServer2 beeline query failed, SQL engine not running or wrong jdbc-url / options"
    exit $CRITICAL
}

check_hiveserver2_beeline
