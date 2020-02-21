#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2019-09-29 12:11:06 +0100 (Sun, 29 Sep 2019)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# ported out from Nagios Plugins Makefile

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$srcdir/.."

# shellcheck disable=SC1090
#. "$srcdir/bash-tools/lib/utils.sh"

ZOOKEEPER_VERSION="${ZOOKEEPER_VERSION:-3.4.12}"

TARBALL="zookeeper-${ZOOKEEPER_VERSION}.tar.gz"
TARDIR="${TARBALL%.tar.gz}"

make="${MAKE:-make}"

sudo=""
if [ $EUID != 0 ]; then
    sudo=sudo
fi


check_installed(){
    echo "checking zkperl installation:"
    local cmd="perl -e 'use Net::ZooKeeper'"
    echo "$cmd"
    eval $cmd

}

if [ -z "${FORCE:-}" ] && check_installed; then
    echo "Already installed, no need to re-install"
    exit 0
fi

if [ -d "$TARDIR" ]; then
    echo "Existing zookeeper directory found: $TARDIR"
else
    if ! [ -f "$TARBALL" ]; then
        echo "Downloading ZooKeeper tarball"
        wget -qO "$TARBALL" "http://www.apache.org/dyn/closer.lua?filename=zookeeper/$TARDIR/$TARBALL&action=download" ||
        wget -t 2 --retry-connrefused -qO "$TARBALL" "https://archive.apache.org/dist/zookeeper/$TARDIR/$TARBALL"
        echo
    fi
    echo "unpacking tarball $TARBALL"
    tar zxf "$TARBALL"
    echo "tarball unpacked"
    echo
fi

cd "$TARDIR/src/c"

configure_make(){
    echo "Running ./configure && $make"
    ./configure &&
    "$make"
}

# if first compile fails, it's probably newer GCC so set -Wno-error=format-overflow=
# https://issues.apache.org/jira/projects/ZOOKEEPER/issues/ZOOKEEPER-3293
configure_make || {
    export CFLAGS="${CFLAGS:-} -Wno-error=format-overflow=";
    echo "re-running $CFLAGS ./configure && make"
    CFLAGS="$CFLAGS" configure_make
}

$sudo "$make" install

cd "../contrib/zkperl"

perl Makefile.PL --zookeeper-include=/usr/local/include --zookeeper-lib=/usr/local/lib

make_lib(){
    # eval prevents error:
    # LD_RUN_PATH=/usr/local/lib: No such file or directory
    eval $sudo LD_RUN_PATH=/usr/local/lib "$make"
}

make_lib || {
    perl -pi -e 's/-Werror=format-security//' Makefile
    make_lib
}

$sudo "$make" install

echo
check_installed

echo
echo "ZooKeeper Perl libary (zkperl) installed successfully"
