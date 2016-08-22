#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-08-22 16:17:31 +0100 (Mon, 22 Aug 2016)
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
#                               T r a v i s   C I
# ============================================================================ #
"

./check_travis_ci_last_build.py -r HariSekhon/nagios-plugins || :
hr
./check_travis_ci_last_build.py -r HariSekhon/nagios-plugins -v || :
hr
./check_travis_ci_last_build.py -r HariSekhon/tools || :
hr
./check_travis_ci_last_build.py -r HariSekhon/spotify-tools || :
hr
./check_travis_ci_last_build.py -r HariSekhon/pytools || :
hr
./check_travis_ci_last_build.py -r HariSekhon/pylib || :
hr
./check_travis_ci_last_build.py -r HariSekhon/lib || :
hr
./check_travis_ci_last_build.py -r HariSekhon/lib-java || :
hr
./check_travis_ci_last_build.py -r HariSekhon/nagios-plugin-kafka || :
hr
./check_travis_ci_last_build.py -r HariSekhon/spark-apps || :
hr
echo; echo
