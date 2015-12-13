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

set -eu
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                                   M y S Q L
# ============================================================================ #
"

# MYSQL_HOST, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD obtained via .travis.yml
export MYSQL_HOST="${MYSQL_HOST:-localhost}"
export MYSQL_DATABASE="${MYSQL_DATABASE:-mysql}"
export MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
export MYSQL_USER="${MYSQL_USER:-travis}"

$perl -T $I_lib ./check_mysql_config.pl --warn-on-missing -v
hr
$perl -T $I_lib ./check_mysql_query.pl -q "SHOW TABLES IN information_schema" -o CHARACTER_SETS -v
# test Unix Socket connection
$perl -T $I_lib ./check_mysql_query.pl -u root -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -o "'root'@'localhost'" -v
# test TCP connection
$perl -T $I_lib ./check_mysql_query.pl -H localhost -u root -d information_schema -q "SELECT * FROM user_privileges LIMIT 1"  -o "'root'@'localhost'" -v

echo; echo
