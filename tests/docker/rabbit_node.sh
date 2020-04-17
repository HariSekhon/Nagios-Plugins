#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2020-04-17 20:06:17 +0100 (Fri, 17 Apr 2020)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x
srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1090
. "$srcdir/rabbit_load_env_vars.sh"

vars="$(env | grep ^RABBITMQ | sed 's/=.*//')"

env_opts=""
for var in $vars; do
    env_opts+=" -e $var"
done
if [ -n "${DEBUG:-}" ]; then
    env_opts+=" -e DEBUG"
fi

network="$(docker network ls | awk '/nagios.?plugins_rabbitmq/{print $2}' | head -n1)"

# shellcheck disable=SC2086
docker run --rm -ti --name rabbitmq-node $env_opts --network "$network" harisekhon/rabbitmq-cluster:"${VERSION:-latest}"
