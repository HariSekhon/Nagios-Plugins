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
#  http://www.linkedin.com/in/harisekhon
#

# intended only to be sourced by utils.sh
#
# split from utils.sh as this is specific to this repo

set -eu
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

${perl:-perl} -e 'use Net::ZooKeeper' &>/dev/null && zookeeper_built="true" || zookeeper_built=""

is_zookeeper_built(){
    if [ -n "$zookeeper_built" ]; then
        return 0
    else
        return 1
    fi
}

# This is a relatively expensive function do not overuse this
isExcluded(){
    local prog="$1"
    [[ "$prog" =~ ^\* ]] && return 0
    [[ "$prog" =~ ^\.\/\. ]] && return 0
    [[ "$prog" =~ ^\.[[:alnum:]] ]] && return 0
    [[ "$prog" = "check_puppet.rb" ]] && return 0
    # temporarily disable check_kafka.pl check as there is an upstream library breakage
    #[[ "$prog" = "check_kafka.pl" ]] && return 0
    [[ "$prog" =~ *TODO* ]] && return 0
    # Kafka module requires Perl >= 5.10, skip when running tests on 5.8 for CentOS 5 for which everything else works
    if [ "${PERL_MAJOR_VERSION:-}" = "5.8" ]; then
        [ "$prog" = "check_kafka.pl" ] && { echo "skipping check_kafka.pl on Perl 5.8 since the Kafka CPAN module requires Perl >= 5.10"; return 0; }
        [[ "$prog" =~ check_mongodb_.*.pl ]] && { echo "skipping check_mongodb_*.pl on Perl 5.8 since the MongoDB module requires Type::Tiny::XS which breaks for some unknown reason"; return 0; }
    fi
    grep -q "use[[:space:]]\+utils" "$prog" && { echo "skipping $prog due to use of utils.pm from standard nagios plugins collection which may not be available"; return 0; }
    # ignore zookeeper plugins if Net::ZooKeeper module is not available
    if grep -q "Net::ZooKeeper" "$prog" && ! is_zookeeper_built; then
        echo "skipping $prog due to Net::ZooKeeper dependency not having been built (do 'make zookeeper' if intending to use this plugin)"
        return 0
    fi
    [ -n "${NO_GIT:-}" ] && return 1
    # this external git check is expensive, skip it when in CI as using fresh git checkouts
    is_CI && return 1
    if which git &>/dev/null; then
        commit="$(git log "$prog" | head -n1 | grep 'commit')"
        if [ -z "$commit" ]; then
            return 0
        fi
    fi
    return 1
}
