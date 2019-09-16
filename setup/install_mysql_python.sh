#!/usr/bin/env bash
#
#  Author: Hari Sekhon
#  Date: 2019-09-16
#
#  https://github.com/harisekhon/devops-bash-tools
#
#  License: see accompanying LICENSE file
#
#  https://www.linkedin.com/in/harisekhon
#

# Installs MySQL-python dependencies on Mac as needs 2 packages that conflict
#
# solution from:
#
# https://stackoverflow.com/a/51483898

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(uname -s)" = Darwin ]; then
    echo "Running workaround installation for MySQL-Python on Mac OS X"
    set -x
    # avoid erroring if it is already installed but not latest version
    brew install --force mysql openssl || :
    brew unlink mysql
    brew install --force mysql-connector-c || :
    brew link mysql-connector-c
    #sed -i -e 's/libs="$libs -l "/libs="$libs -lmysqlclient -lssl -lcrypto"/g' /usr/local/bin/mysql_config
    # handled in ../bash-tools/python_pip_install.sh
    #export OPENSSL_INCLUDE=/usr/local/opt/openssl/include
    #export OPENSSL_LIB=/usr/local/opt/openssl/lib
    #export LIBRARY_PATH="${LIBRARY_PATH:-}:/usr/local/opt/openssl/lib/"
    "$srcdir/../bash-tools/python_pip_install.sh" MySQL-python
    brew unlink mysql-connector-c
    brew link --overwrite mysql
    python -c 'import MySQLdb'
    echo "SUCCESS!!"
else
    echo "MySQL-Python workaround install only needed on Mac, install via regular methods on other platforms"
fi
