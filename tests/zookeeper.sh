#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-11-11 19:49:15 +0000 (Wed, 11 Nov 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

set -eu
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/";

. tests/travis.sh

echo "
# ============================================================================ #
#                           Z o o K e e p e r
# ============================================================================ #
"

export ZOOKEEPER_HOST="${ELASTICSEARCH_HOST:-localhost}"

ZOOKEEPER_VERSION=3.4.6
#zookeeper="zookeeper-$ZOOKEEPER_VERSION"
#TAR="$zookeeper.tgz"

#if ! [ -e "$TAR" ]; then
#    echo "fetching zookeeper tarball '$TAR'"
#    wget "http://www.us.apache.org/dist/zookeeper/zookeeper-$zookeeper_VERSION/$TAR"
#    echo
#fi

#if ! [ -d "$zookeeper" ]; then
#    echo "unpacking zookeeper"
#    tar zxf "$TAR"
#    echo
#fi

"$zookeeper/bin/zkServer.sh" &
sleep 10

cd "$srcdir/..";
echo
hr
$perl -T $I_lib ./check_zookeeper.pl -s -w 10 -c 20 -v
hr
$perl -T $I_lib ./check_zookeeper_config.pl -C ../$zookeeper/config/zoo_sample.cfg -v
hr
$perl -T $I_lib ./check_zookeeper_child_znodes.pl -z / -v
hr
$perl -T $I_lib ./check_zookeeper_znode.pl -z / -v -n --child-znodes
hr

echo; echo
