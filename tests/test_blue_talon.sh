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
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/..";

. ./tests/utils.sh

echo "
# ============================================================================ #
#                              B l u e   T a l o n
# ============================================================================ #
"

export BLUE_TALON_HOST="${BLUE_TALON_HOST:-trial.bluetalon.com}"
export BLUE_TALON_PORT="${BLUE_TALON_PORT:-443}"
export BLUE_TALON_USER="${BLUE_TALON_USER:-btadminuser}"
export BLUE_TALON_PASSWORD="${BLUE_TALON_PASSWORD:-P@ssw0rd}"
export BLUE_TALON_SSL="-S"
if [ -n "${BLUE_TALON_NO_SSL:-}" ]; then
    export BLUE_TALON_SSL=""
fi

./check_blue_talon_masking_functions.py $BLUE_TALON_SSL -v -w 400 -c 1000
hr
./check_blue_talon_policies.py $BLUE_TALON_SSL -v -w 100 -c 200
hr
./check_blue_talon_policy_deployment.py $BLUE_TALON_SSL -v -w 0:100000000 -c 0:20000000000
hr
./check_blue_talon_resource_domains.py $BLUE_TALON_SSL -v -w 10 -c 20
hr
./check_blue_talon_resources.py $BLUE_TALON_SSL -v -w 100 -c 200
hr
./check_blue_talon_rules.py $BLUE_TALON_SSL -v -w 100 -c 200
hr
./check_blue_talon_user_domains.py $BLUE_TALON_SSL -v -w 10 -c 20
hr
./check_blue_talon_version.py $BLUE_TALON_SSL -v
hr
echo
