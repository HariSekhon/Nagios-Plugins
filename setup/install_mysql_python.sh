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

#sudo=""
#[ $EUID -eq 0 ] || sudo=sudo

check_mysql_python(){
    python -c 'import MySQLdb'
}

if [ "$(uname -s)" = Darwin ]; then
    echo "Running workaround installation for MySQL-Python on Mac OS X"
    if check_mysql_python 2>/dev/null; then
        echo "MySQLdb is already installed, skipping installation"
        exit 0
    fi
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
    "$srcdir/../bash-tools/python_pip_install.sh" mysqlclient  # forked replacement for MySQL-python with Python 3 support
    brew unlink mysql-connector-c
    brew link --overwrite mysql
    check_mysql_python
    echo "SUCCESS!!"
else
    # hacky workaround to changes in MariaDB :-(
    # not necessary with newer fork 'mysqlclient' which replaces MySQL-python
#    if rpm -q mariadb-devel &>/dev/null ||
#       apk info mariadb-dev &>/dev/null; then
#        echo "Patching MariaDB library header to be compatible for MySQL-python library"
#        $sudo sed -i.bak '/st_mysql_options options;/a unsigned int reconnect;' /usr/include/mysql/mysql.h
#    fi
    echo "mysqlclient (MySQL-Python replacement) on Linux to be installed by pip"
fi
